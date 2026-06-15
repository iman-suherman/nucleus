import Foundation
import NucleusKit

public enum NotesDrivePaths {
    public static let rootFolder = "Nucleus"

    public static func folderPath(_ folder: NoteFolder) -> String {
        "\(rootFolder)/\(folder.rawValue)"
    }
}

public enum NotesMarkdown {
    public static func dailyNoteTitle(for date: Date = Date()) -> String {
        NucleusFormatters.dayHeader.string(from: date)
    }

    public static func meetingNoteTemplate(title: String, date: Date = Date()) -> String {
        """
        # \(title)
        Date: \(NucleusFormatters.dayHeader.string(from: date))

        ## Discussion
        -

        ## Actions
        -
        """
    }

    public static func clipboardNoteTemplate(from content: String, source: String, capturedAt: Date = Date()) -> String {
        """
        # Clipboard Note
        Copied from: \(source)
        Date: \(NucleusFormatters.dayHeader.string(from: capturedAt))

        ```
        \(content)
        ```
        """
    }

    public static func credentialNoteTemplate(title: String, folder: NoteFolder) -> String {
        switch folder {
        case .passwords:
            return """
            # \(title)
            Service:
            Username:
            Password:
            URL:
            Notes:
            """
        case .credentials:
            return """
            # \(title)
            Label:
            Username / ID:
            Secret:
            Expires:
            Notes:
            """
        default:
            return "# \(title)\n"
        }
    }
}

public enum DriveNotesClient {
    public static func ensureFolder(accessToken: String, path: String) async throws -> String {
        var listComponents = URLComponents(string: "https://www.googleapis.com/drive/v3/files")!
        listComponents.queryItems = [
            URLQueryItem(name: "q", value: "name='\(path.components(separatedBy: "/").last ?? path)' and mimeType='application/vnd.google-apps.folder' and trashed=false"),
            URLQueryItem(name: "fields", value: "files(id,name)"),
        ]

        var listRequest = URLRequest(url: listComponents.url!)
        listRequest.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let (listData, listResponse) = try await URLSession.shared.data(for: listRequest)
        guard let listHTTP = listResponse as? HTTPURLResponse, (200..<300).contains(listHTTP.statusCode) else {
            throw URLError(.badServerResponse)
        }

        let listJSON = try JSONSerialization.jsonObject(with: listData) as? [String: Any]
        if let files = listJSON?["files"] as? [[String: Any]], let first = files.first, let id = first["id"] as? String {
            return id
        }

        var createRequest = URLRequest(url: URL(string: "https://www.googleapis.com/drive/v3/files")!)
        createRequest.httpMethod = "POST"
        createRequest.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        createRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        createRequest.httpBody = try JSONSerialization.data(withJSONObject: [
            "name": path.components(separatedBy: "/").last ?? path,
            "mimeType": "application/vnd.google-apps.folder",
        ])

        let (createData, createResponse) = try await URLSession.shared.data(for: createRequest)
        guard let createHTTP = createResponse as? HTTPURLResponse, (200..<300).contains(createHTTP.statusCode) else {
            throw URLError(.badServerResponse)
        }
        let createJSON = try JSONSerialization.jsonObject(with: createData) as? [String: Any]
        guard let folderID = createJSON?["id"] as? String else {
            throw URLError(.cannotParseResponse)
        }
        return folderID
    }

    public static func uploadMarkdown(
        accessToken: String,
        fileName: String,
        markdown: String,
        folderID: String
    ) async throws -> String {
        let boundary = "Boundary-\(UUID().uuidString)"
        var body = Data()
        let metadata: [String: Any] = [
            "name": fileName,
            "mimeType": "text/markdown",
            "parents": [folderID],
        ]
        let metadataJSON = try JSONSerialization.data(withJSONObject: metadata)

        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Type: application/json; charset=UTF-8\r\n\r\n".data(using: .utf8)!)
        body.append(metadataJSON)
        body.append("\r\n".data(using: .utf8)!)
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Type: text/markdown\r\n\r\n".data(using: .utf8)!)
        body.append(Data(markdown.utf8))
        body.append("\r\n".data(using: .utf8)!)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        var request = URLRequest(url: URL(string: "https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/related; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let fileID = json?["id"] as? String else {
            throw URLError(.cannotParseResponse)
        }
        return fileID
    }
}

public enum NotesSyncEngine {
    public static func uploadNote(
        note: NoteDocument,
        accessToken: String
    ) async throws -> String {
        _ = try await DriveNotesClient.ensureFolder(accessToken: accessToken, path: NotesDrivePaths.rootFolder)
        let folderID = try await DriveNotesClient.ensureFolder(
            accessToken: accessToken,
            path: NotesDrivePaths.folderPath(note.folder)
        )
        return try await DriveNotesClient.uploadMarkdown(
            accessToken: accessToken,
            fileName: "\(note.title).md",
            markdown: note.markdown,
            folderID: folderID
        )
    }
}
