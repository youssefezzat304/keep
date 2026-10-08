"use client";

import { useRef } from "react";
import { motion, useReducedMotion, useScroll, useTransform } from "motion/react";

/** A small scroll response draws the preview into the story without taking over scrolling. */
export function ScrollPreview({ children, variant = "hero" }: { children: React.ReactNode; variant?: "hero" | "zen" }) {
  const ref = useRef<HTMLDivElement>(null);
  const reduced = useReducedMotion();
  const { scrollYProgress } = useScroll({ target: ref, offset: ["start end", "end start"] });
  const y = useTransform(scrollYProgress, [0, 1], variant === "hero" ? [28, -28] : [20, -20]);
  const rotate = useTransform(scrollYProgress, [0, 1], variant === "hero" ? [-2.8, 0.8] : [0, 0]);
  return <div ref={ref} className={`scroll-preview scroll-preview-${variant}`}>
    <motion.div className="preview-motion" style={reduced ? undefined : { y, rotate }}>{children}</motion.div>
  </div>;
}
