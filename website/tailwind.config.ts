import type { Config } from "tailwindcss";

const config: Config = {
  content: ["./src/**/*.{js,ts,jsx,tsx,mdx}"],
  theme: {
    extend: {
      colors: {
        brand: {
          navy: "#1a1e2b",
          navyLight: "#232a3b",
          navyElevated: "#2d3447",
          accent: "#8da2fb",
          accentHover: "#a4b4fc",
          accentDark: "#5c72d6",
          silver: "#b0b3b8",
          silverLight: "#c8cad0",
          // Aliases used across components
          blue: "#8da2fb",
          blueDark: "#232a3b",
          purple: "#b0b3b8",
          green: "#a4b4fc",
        },
      },
      boxShadow: {
        card: "0 18px 50px rgba(0, 0, 0, 0.45), 0 0 0 1px rgba(255, 255, 255, 0.04)",
        soft: "0 8px 30px rgba(0, 0, 0, 0.35)",
      },
    },
  },
  plugins: [],
};

export default config;
