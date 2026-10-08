import Image from "next/image";

export function Capture({ name, alt, priority = false, className = "" }: {
  name: "focus" | "timesheet" | "calendar" | "habits" | "stats" | "exports" | "menu";
  alt: string;
  priority?: boolean;
  className?: string;
}) {
  const menu = name === "menu";
  const sizes = menu ? "(max-width: 767px) 260px, 280px" : "(max-width: 767px) 92vw, (max-width: 1023px) 85vw, 65vw";
  const sources = (menu ? [380, 760] : [720, 1200, 1920]).map(width =>
    `/screenshots/${name}-light${width === (menu ? 760 : 1920) ? "" : `-${width}`}.webp ${width}w`).join(", ");
  return (
    <div className={`capture ${className}`}>
      {priority && <link rel="preload" as="image" imageSrcSet={sources} imageSizes={sizes} fetchPriority="high" />}
      <picture>
        <source srcSet={sources} sizes={sizes} />
        <Image src={`/screenshots/${name}-light.webp`} alt={alt} width={menu ? 760 : 1920} height={menu ? 1360 : name === "exports" ? 960 : 1440}
          sizes={sizes} loading={priority ? "eager" : "lazy"} fetchPriority={priority ? "high" : undefined} />
      </picture>
    </div>
  );
}
