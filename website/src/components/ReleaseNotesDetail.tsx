import { releaseNotesSections, type ReleaseNotes } from "@/lib/registry";

function ReleaseNotesBullet({ text }: { text: string }) {
  return (
    <li className="flex gap-2.5 text-sm leading-relaxed text-slate-300">
      <span
        aria-hidden
        className="mt-[0.45rem] h-1.5 w-1.5 shrink-0 rounded-full bg-brand-blue/70"
      />
      <span>{text}</span>
    </li>
  );
}

export function ReleaseNotesDetail({ notes }: { notes?: ReleaseNotes }) {
  const sections = releaseNotesSections(notes);

  if (sections.length === 0) {
    return (
      <p className="text-sm leading-relaxed text-slate-500">
        Detailed release notes for this version are not available yet.
      </p>
    );
  }

  return (
    <div className="space-y-5">
      {sections.map((section) => (
        <div key={section.id}>
          <h4 className="text-sm font-semibold text-slate-200">{section.title}</h4>
          <ul className="mt-2.5 space-y-2">
            {section.items.map((item) => (
              <ReleaseNotesBullet key={item} text={item} />
            ))}
          </ul>
        </div>
      ))}
    </div>
  );
}
