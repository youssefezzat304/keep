import Image from "next/image";
import { ArrowRight, ArrowUpRight, Desktop, HardDrives, Headphones } from "@phosphor-icons/react/dist/ssr";
import { Capture } from "@/components/capture";
import { Reveal } from "@/components/reveal";
import { ScrollPreview } from "@/components/scroll-preview";
import { WorkspaceTour } from "@/components/workspace-tour";
import { DownloadLink } from "@/components/download-link";

const github = "https://github.com/youssefezzat304/keep";

export default function Home() {
  return <>
    <a className="skip-link" href="#main">Skip to content</a>
    <header className="site-header">
      <div className="header-inner">
        <a className="brand" href="#" aria-label="Keep home"><Image src="/brand/keep-icon.webp" alt="" width={38} height={38} /><span>keep</span></a>
        <nav aria-label="Main navigation"><a href="#workspace">The workspace</a><a href="#zen">Your space</a><a href="#mac">Made for Mac</a></nav>
        <a href="#download" className="button button-small">Get Keep<ArrowUpRight size={16} aria-hidden="true" /></a>
      </div>
    </header>
    <main id="main">
      <section className="hero container" aria-labelledby="hero-heading">
        <div className="hero-copy">
          <span className="eyebrow">A little space for you</span>
          <h1 id="hero-heading">Make room<br />for <span>focus.</span></h1>
          <p>Your timers, tasks, habits, and music. Together in one cozy workspace for your Mac.</p>
          <div className="hero-actions"><a className="button button-primary" href="#download">Get Keep<ArrowUpRight size={19} aria-hidden="true" /></a><a className="text-link" href="#workspace">Meet the workspace<ArrowRight size={20} aria-hidden="true" /></a></div>
          <p className="hero-note">Every Keep feature is free.</p>
        </div>
        <div className="hero-visual">
          <ScrollPreview><Capture name="focus" alt="Keep’s native Mac app brings focus timers, music, projects, and tasks into one workspace" priority /></ScrollPreview>
        </div>
      </section>

      <section id="workspace" className="workspace-section container" aria-labelledby="workspace-heading">
        <Reveal className="section-intro"><h2 id="workspace-heading">A rhythm that<br /><span>feels like you.</span></h2><p>Focus, your Dashboard, and the progress you’re making. All in one place.</p></Reveal>
        <WorkspaceTour />
      </section>

      <section id="goals" className="goals-section container" aria-labelledby="goals-heading">
        <Reveal><h2 id="goals-heading">A little direction.<br /><span>Room to grow.</span></h2><p className="section-description">Set goals that fit your week, with a little flexibility for the days that don’t go to plan.</p></Reveal>
        <Reveal><dl className="goals-list">
          <div><dt>A weekly focus goal.</dt><dd>Choose how much time you want to make for focused work across all your projects.</dd></div>
          <div><dt>Targets for each project.</dt><dd>Set a weekly Goal to aim for and an At least target for a busy week. Follow your progress in Stats.</dd></div>
          <div><dt>Habits at your pace.</dt><dd>Choose daily check-ins, minutes, or repetitions. Add weekly targets and decide which days your habits belong on.</dd></div>
        </dl></Reveal>
      </section>

      <section id="exports" className="export-section container" aria-labelledby="export-heading">
        <Reveal><Capture name="exports" alt="Keep’s Export settings with dataset, date range, project filter, and a native Export action" /></Reveal>
        <Reveal className="export-copy"><h2 id="export-heading">Take your work<br /><span>with you.</span></h2><p className="section-description">Export your Timesheet and Calendar as CSV, or save your Stats as a ZIP of CSV reports. Choose dates and projects before saving.</p><p className="export-detail">Ready for your spreadsheet. Included for free.</p></Reveal>
      </section>

      <section id="music" className="music-section container" aria-labelledby="music-heading">
        <Reveal><span className="music-label"><Headphones size={22} aria-hidden="true" />The built-in music player</span><h2 id="music-heading">Find your<br /><span>focus soundtrack.</span></h2><p className="section-description">Settle into lo-fi beats or an ambient playlist. Play, pause, skip, and adjust the volume without leaving your workspace.</p></Reveal>
        <Reveal><dl className="music-sources">
          <div><dt>Discover on Audius.</dt><dd>Start with Keep’s lo-fi selection, or add public Audius artists and playlists to make the music your own.</dd></div>
          <div><dt>Bring your Music library.</dt><dd>Browse your Mac’s Music library and playlists in Keep, then control playback from Focus, Zen, or the menu bar.</dd></div>
        </dl></Reveal>
      </section>

      <section id="zen" className="zen-section container" aria-labelledby="zen-heading">
        <Reveal className="zen-intro"><h2 id="zen-heading">Your space.<br /><span>Your own view.</span></h2><p>Choose your own wallpapers from a folder of images or MP4 videos. Open Zen to fill the screen with your favorites, with music and timers always within reach.</p></Reveal>
        <ScrollPreview variant="zen"><figure className="zen-capture"><picture><source srcSet="/screenshots/zen-720.webp 720w, /screenshots/zen-1200.webp 1200w, /screenshots/zen.webp 1920w" sizes="(max-width: 767px) 92vw, 90vw" /><Image src="/screenshots/zen.webp" alt="Keep’s Zen mode fills the screen with a cozy autumn wallpaper, with music controls and timers at the bottom" width={1920} height={1200} sizes="(max-width: 767px) 92vw, 90vw" /></picture></figure></ScrollPreview>
        <div className="zen-details"><p><Headphones size={20} aria-hidden="true" />Your music, right here.</p><p>Your wallpapers. Your kind of quiet.</p></div>
      </section>

      <section id="mac" className="mac-section container" aria-labelledby="mac-heading">
        <div className="menu-visual"><Reveal><Capture name="menu" alt="Keep’s menu bar panel with timer controls, today’s tasks, and music" /></Reveal></div>
        <div className="mac-copy">
          <Reveal><h2 id="mac-heading">A small home<br />on your Mac.</h2><p className="section-description">Start a timer, check off a task, or change the music. Keep is right there in your menu bar.</p></Reveal>
          <div className="native-features">
            <Reveal><div><Desktop size={25} weight="duotone" aria-hidden="true" /><h3>Feels right at home.</h3><p>A native Mac app, with familiar controls and shortcuts.</p></div></Reveal>
            <Reveal><div><HardDrives size={25} weight="duotone" aria-hidden="true" /><h3>Your work, kept close.</h3><p>Your projects, tasks, and focus history are saved locally.</p></div></Reveal>
          </div>
        </div>
      </section>

      <section id="download" className="download-section container" aria-labelledby="download-heading">
        <Reveal><Image className="download-icon" src="/brand/keep-icon.webp" alt="Keep’s terracotta leaf app icon" width={112} height={112} /><h2 id="download-heading">Every feature.<br /><span>Completely free.</span></h2><p>Focus timers, Dashboard, habits, goals, a music player, custom wallpapers, and exports. No subscriptions or paid upgrades.</p></Reveal>
        <DownloadLink />
      </section>
    </main>
    <footer className="site-footer container"><a className="brand footer-brand" href="#"><Image src="/brand/keep-icon.webp" alt="" width={30} height={30} /><span>keep</span></a><p>A little space to focus.</p><a className="text-link" href={github}>Find us on GitHub<ArrowUpRight size={17} aria-hidden="true" /></a></footer>
  </>;
}
