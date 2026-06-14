import Image from "next/image";
import { BRAND_NAME } from "@/lib/brand";

type AppHeroIconProps = {
  className?: string;
  priority?: boolean;
};

export function AppHeroIcon({ className = "", priority = false }: AppHeroIconProps) {
  return (
    <div className={`app-hero ${className}`.trim()}>
      <div aria-hidden className="app-hero-glow" />
      <div aria-hidden className="app-hero-core-glow" />
      <div aria-hidden className="app-hero-ring" />
      <div aria-hidden className="app-hero-sweep" />
      <Image
        src="/app-icon.png"
        alt={`${BRAND_NAME} app icon`}
        width={1024}
        height={1024}
        priority={priority}
        unoptimized
        sizes="(max-width: 1024px) 90vw, 32rem"
        className="app-hero-image relative z-10 h-auto w-full object-contain drop-shadow-[0_16px_40px_rgba(0,122,255,0.35)]"
      />
    </div>
  );
}
