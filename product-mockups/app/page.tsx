"use client";
/* oxlint-disable next/no-img-element -- Static PNGs also deploy to S3 without an image optimization server. */
import { useState } from "react";
import release from "./release.json";
import { Switch } from "@/components/ui/switch";
import {
  ArrowUpRight,
  ArrowDown,
  Cpu,
  LockKeyhole,
  FolderHeart,
  Sparkles,
} from "lucide-react";
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
              Image generation runs on your Mac. The app has no image uploads,
              accounts, or telemetry. Download and prepare your models, then
              create offline.
            </p>
          </article>
          <article>
            <FolderHeart />
            <h3>A library that belongs to you.</h3>
            <p>
              Favorites, tags, album membership, prompts, and seeds travel with
              your PNGs. Your pictures are files you can take anywhere.
            </p>
          </article>
        </div>
      </section>
      <section className="models" id={`${id}-models`}>
        <span className="eyebrow">
          THREE MODEL FAMILIES. ONE NATIVE WORKSPACE.
        </span>
        <div className="model-names">
          <span>Z-Image-Turbo</span>
          <span>Qwen-Image-2512</span>
          <span>FLUX.2 klein 4B</span>
        </div>
        <p>
          Choose a model to match your idea and your Mac. Generate and edit with
          each, then finish with 2× or 4× Real-ESRGAN upscaling.
        </p>
      </section>
      <section className="requirements" id={`${id}-requirements`}>
        <Cpu />
        <div>
          <h3>At home on Apple Silicon.</h3>
          <p>
            macOS 15 or later · Memory and storage requirements vary by model.
            <br />
            An internet connection is needed for model downloads.
          </p>
        </div>
      </section>
      <footer>
        <Brand />
        <span>© 2026 James Brink. All rights reserved.</span>
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
    <main className="safelight" data-theme={dark ? "dark" : "light"} id="top">
      <a className="skip-link" href="#dark-features">
        Skip to features
      </a>
      <Nav id="dark" dark={dark} onTheme={setDark} />
      <section className="dark-hero">
        <div className="hero-copy">
          <span className="eyebrow">
            <span className="live-dot" /> LOCAL IMAGE GENERATION FOR MAC
          </span>
          <h1>
            A little imagination.
            <br />
            <em>Entirely yours.</em>
          </h1>
          <p>
            Turn words into images in a creative space that feels at home on
            your Mac. Powerful models. Native controls. Everything stays with
            you.
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
            src="/images/robot.png"
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
        <span>GENERATE · EDIT · UPSCALE · COLLECT</span>
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
      <Features id="dark" />
    </main>
  );
}
