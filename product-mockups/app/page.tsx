'use client';
/* oxlint-disable next/no-img-element -- Static PNGs also deploy to S3 without an image optimization server. */
import { useState } from 'react';
import release from './release.json';
import GettingStarted from './getting-started';
import { Switch } from '@/components/ui/switch';
import {
  ArrowUpRight,
  ArrowDown,
  LockKeyhole,
  FolderHeart,
  Sparkles,
} from 'lucide-react';
function Brand() {
  return (
    <a className="brand" href="#top">
      <span className="brand-mark" aria-hidden="true" />
      Zephra
    </a>
  );
}
function Nav({
  id,
  dark,
  onTheme,
}: {
  id: string;
  dark: boolean;
  onTheme: (value: boolean) => void;
}) {
  return (
    <header className="nav">
      <Brand />
      <nav aria-label="Product">
        <label className="theme-control" htmlFor={`${id}-theme`}>
          <span>Dark mode</span>
          <Switch
            id={`${id}-theme`}
            checked={dark}
            onCheckedChange={onTheme}
            aria-label="Dark mode"
          />
        </label>
        <a href={`#${id}-features`}>The app</a>
        <a href={`#${id}-models`}>Models</a>
        <a className="guide-nav-link" href="/guide/">User guide</a>
        <a className="nav-cta" href={`#${id}-requirements`}>
          Made for Mac <ArrowUpRight size={15} />
        </a>
      </nav>
    </header>
  );
}
function Features({ id }: { id: string }) {
  return (
    <>
      <section className="features" id={`${id}-features`}>
        <div className="section-intro">
          <span className="eyebrow">YOUR OWN CREATIVE SPACE</span>
          <h2>
            From a thought.
            <br />
            To something worth keeping.
          </h2>
        </div>
        <div className="feature-grid">
          <article>
            <Sparkles />
            <h3>Make it. Make it yours.</h3>
            <p>
              Start with a prompt or a reference image. Explore variations,
              queue your next idea, and upscale the one you love.
            </p>
          </article>
          <article>
            <LockKeyhole />
            <h3>Your imagination stays here.</h3>
            <p>
              Image and video generation run on your Mac. The app has no image
              uploads, accounts, or telemetry. Download and prepare your models,
              then create offline.
            </p>
          </article>
          <article>
            <FolderHeart />
            <h3>A library that belongs to you.</h3>
            <p>
              Favorites, tags, album membership, prompts, and seeds travel with
              your PNGs. Keep a video’s MP4 and poster PNG together to take its
              details with it.
            </p>
          </article>
        </div>
      </section>
      <section className="models" id={`${id}-models`}>
        <span className="eyebrow">
          FIVE MODEL FAMILIES. ONE NATIVE WORKSPACE.
        </span>
        <div className="model-names">
          <span>Z-Image-Turbo</span>
          <span>Qwen-Image-2512</span>
          <span>FLUX.2 klein 4B</span>
          <span>Wan 2.2</span>
          <span>LTX-2.5</span>
        </div>
        <p>
          Generate and edit images with Z-Image-Turbo, Qwen-Image, or FLUX.2
          klein. Create video with Wan 2.2 or LTX-2.5, including sound with
          LTX-2.5’s audio variant. Finish still images with 2× or 4× Real-ESRGAN
          upscaling.
        </p>
      </section>
      <GettingStarted id={id} />
      <footer>
        <Brand />
        <span>© 2026 James Brink. All rights reserved.</span>
        <nav className="footer-links" aria-label="Resources">
          <a href="/guide/">User guide</a>
          <a href="#whats-new">What’s new</a>
          <a href="mailto:dev.urandom.io@gmail.com?subject=Zephra%20support">
            Support
          </a>
        </nav>
        <details className="website-privacy">
          <summary>
            Privacy <span aria-hidden="true">+</span>
          </summary>
          <div className="privacy-content">
            <p>
              Your creativity stays on your Mac. Zephra does not collect your
              prompts, images, or app activity.
            </p>
            <p>
              We use Google Analytics cookies to understand how visitors use
              this website and improve the experience. This includes page
              visits, download clicks, and general device and region
              information. We do not use this data for personalized advertising.
            </p>
          </div>
        </details>
      </footer>
    </>
  );
}
export default function Page() {
  const [dark, setDark] = useState(true);
  return (
    <main className="safelight" data-theme={dark ? 'dark' : 'light'} id="top">
      <a className="skip-link" href="#dark-features">
        Skip to features
      </a>
      <Nav id="dark" dark={dark} onTheme={setDark} />
      <section className="dark-hero">
        <div className="hero-copy">
          <span className="eyebrow">
            <span className="live-dot" /> LOCAL AI IMAGES & VIDEO FOR MAC
          </span>
          <h1>
            A little imagination.
            <br />
            <em>Entirely yours.</em>
          </h1>
          <p>
            Turn words into images and short videos in a creative space that
            feels at home on your Mac. Powerful models. Native controls.
            Everything stays with you.
          </p>
          <a className="button" href={release.url}>
            Download for Mac <ArrowDown size={17} />
          </a>
          <span className="compatibility">
            Built for Apple Silicon · Powered by MLX
          </span>
        </div>
        <div className="hero-art">
          <img
            src="/images/robot-1024.webp"
            srcSet="/images/robot-480.webp 480w, /images/robot-768.webp 768w, /images/robot-1024.webp 1024w"
            sizes="(max-width: 650px) calc(100vw - 48px), (max-width: 1320px) calc((100vw - 151px) / 2.04), 553px"
            width={1024}
            height={1024}
            fetchPriority="high"
            alt="A copper robot reading a newspaper in warm light, generated locally with Zephra"
          />
          <div className="art-caption">
            <span>A quiet moment in copper</span>
            <span>FLUX.2 klein · Made in Zephra</span>
          </div>
          <span className="art-index">01 / A MOMENT, IMAGINED</span>
        </div>
      </section>
      <div className="statement">
        <span>YOUR MAC IS THE STUDIO.</span>
        <p>
          No cloud between
          <br />
          you and your next idea.
        </p>
        <span>GENERATE · ANIMATE · EDIT · COLLECT</span>
      </div>
      <section className="app-section">
        <div>
          <span className="eyebrow">
            A FAMILIAR FEELING. NEW POSSIBILITIES.
          </span>
          <h2>
            A canvas for
            <br />
            your next “what if.”
          </h2>
          <p>
            Watch an image take shape with live previews. Keep ideas moving with
            a generation queue, and find your favorites in a searchable library.
          </p>
        </div>
        <img
          src="/images/app.png"
          width={1299}
          height={769}
          loading="lazy"
          decoding="async"
          alt="Zephra’s maximized macOS window showing completed copper robot artwork and its generation details"
        />
        <small>Zephra app · Completed image · Generated locally</small>
      </section>
      <section className="video-feature" aria-labelledby="video-heading">
        <div>
          <span className="eyebrow">WAN 2.2 + LTX-2.5 WITH SOUND</span>
          <h2 id="video-heading">
            Give your imagination
            <br />
            <em>motion and sound.</em>
          </h2>
          <p>
            Describe a scene and turn it into a short video. Or choose a
            picture, select Animate, and use it as the first frame of something
            new. Choose LTX-2.5’s “with sound” variant to generate audio
            alongside your video, or explore silent clips with Wan 2.2.
          </p>
        </div>
        <div className="video-details">
          <h3>From a still to a story.</h3>
          <p>
            Create clips locally on Apple Silicon, play them right in Zephra,
            and keep them alongside your images. Export as MP4 when you’re ready
            to share.
          </p>
          <p className="video-note">
            Generate segments up to 5 seconds at 24 fps. LTX-2.5 offers
            video-only and “with sound” variants; Wan 2.2 produces silent video.
            Memory and storage needs vary by model and settings.
          </p>
        </div>
      </section>
      <Features id="dark" />
    </main>
  );
}
