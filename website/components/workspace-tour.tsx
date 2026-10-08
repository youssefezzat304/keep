"use client";

import { useEffect, useRef, useState } from "react";
import { Capture } from "./capture";

const chapters = [
  { id: "focus", label: "Focus", title: "One thing at a time.", body: "Pick a project, choose a task, and settle in. A Pomodoro for structure. A Flow timer when you want to stay.", detail: "A clear intention. A little momentum.", image: "focus", alt: "Keep Focus with an active project, Pomodoro and Flow timers, music, and today’s tasks" },
  { id: "timesheet", label: "Timesheet", title: "Your week, added up.", body: "Your Dashboard brings every project into a weekly Timesheet. Review daily totals, see where your hours went, and adjust them when you need to.", detail: "Dashboard · Timesheet", image: "timesheet", alt: "Keep Dashboard Timesheet with daily project totals and a weekly summary" },
  { id: "calendar", label: "Calendar", title: "Give your time a shape.", body: "See your recorded sessions on the Dashboard Calendar. Revisit a day, edit session times, or remove an entry. A clear view of the work you actually did.", detail: "Dashboard · Calendar", image: "calendar", alt: "Keep Dashboard Calendar with recorded focus sessions arranged across the week" },
  { id: "habits", label: "Habits", title: "Little things add up.", body: "Read a chapter. Take a walk. Make something. Set daily goals and weekly targets, then give the habits you care about a place in your day.", detail: "Daily check-ins. A bigger picture.", image: "habits", alt: "Keep Habit tracker with a year of example activity, daily check-ins, and weekly goals" },
  { id: "stats", label: "Stats", title: "See the time you made.", body: "Find your patterns, follow your projects, and look back on the work you put in. Progress you can actually see.", detail: "Your focus, with a little perspective.", image: "stats", alt: "Keep Stats showing recorded focus time, active days, Pomodoros, and project charts" },
] as const;

export function WorkspaceTour() {
  const ref = useRef<HTMLDivElement>(null);
  const [active, setActive] = useState(0);
  useEffect(() => {
    const element = ref.current;
    if (!element) return;
    const media = window.matchMedia("(prefers-reduced-motion: reduce)");
    const update = () => { element.dataset.enhanced = media.matches ? "false" : "true"; };
    update();
    media.addEventListener("change", update);
    const observer = new IntersectionObserver(entries => {
      for (const entry of entries) {
        if (entry.isIntersecting) setActive(Number((entry.target as HTMLElement).dataset.chapter));
      }
    }, { rootMargin: "-35% 0px -35% 0px", threshold: 0 });
    element.querySelectorAll(".tour-step").forEach(step => observer.observe(step));
    const stage = element.querySelector<HTMLElement>(".tour-stage");
    const resizeObserver = new ResizeObserver(() => {
      if (stage) element.style.setProperty("--tour-preview-height", `${stage.offsetHeight}px`);
    });
    if (stage) resizeObserver.observe(stage);
    return () => {
      observer.disconnect();
      resizeObserver.disconnect();
      media.removeEventListener("change", update);
      delete element.dataset.enhanced;
      element.style.removeProperty("--tour-preview-height");
    };
  }, []);

  return <div className="tour" ref={ref}>
    <div className="tour-copy">
      {chapters.map((chapter, index) => <article key={chapter.id} id={chapter.id} className="tour-step" data-chapter={index}>
        <div className="tour-step-copy">
          <h3>{chapter.title}</h3>
          <p>{chapter.body}</p>
          <span className="chapter-detail">{chapter.detail}</span>
        </div>
        <Capture name={chapter.image} alt={chapter.alt} className="tour-inline" />
      </article>)}
    </div>
    <aside className="tour-stage" aria-label="Workspace preview">
      <nav className="tour-tabs" aria-label="Explore the workspace">
        {chapters.map((chapter, index) => <a key={chapter.id} href={`#${chapter.id}`} aria-current={active === index ? "true" : undefined}>{chapter.label}</a>)}
      </nav>
      <div className="tour-screens" data-active={chapters[active].id}>
        {chapters.map((chapter, index) => <div key={chapter.id} className={`tour-screen ${active === index ? "is-active" : ""}`} aria-hidden="true">
          <Capture name={chapter.image} alt="" />
        </div>)}
      </div>
    </aside>
  </div>;
}
