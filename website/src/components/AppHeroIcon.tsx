import Image from "next/image";
import { BRAND_NAME } from "@/lib/brand";

type AppHeroIconProps = {
  className?: string;
  priority?: boolean;
};

export function AppHeroIcon({ className = "", priority = false }: AppHeroIconProps) {
  return (
    <div className={`app-hero ${className}`.trim()}>
      <Image
        src="/app-icon.png"
        alt={`${BRAND_NAME} app icon`}
        width={1024}
        height={1024}
        priority={priority}
        unoptimized
        sizes="(max-width: 1024px) 90vw, 32rem"
        className="app-hero-image h-full w-full object-contain"
      />
    </div>
  );
}
