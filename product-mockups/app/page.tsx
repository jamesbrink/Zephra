'use client';
import { Tabs, TabsList, TabsTrigger, TabsContent } from '@/components/ui/tabs';
import {
  ArrowUpRight,
  ArrowDown,
  Cpu,
  LockKeyhole,
  FolderHeart,
  Sparkles,
} from 'lucide-react';
const concepts = ['Safelight', 'Native', 'Atelier'];
function Brand() {
  return (
    <a className="brand" href="#">
      <img src="/images/icon.png" alt="" />
      Zephra
    </a>
  );
}
function Nav({ id }: { id: string }) {
  return (
    <header className="nav">
      <Brand />
      <nav aria-label="Product">
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
              Image generation runs on your Mac. No image uploads, accounts, or
              telemetry. Download your models once, then create offline.
            </p>
          </article>
          <article>
            <FolderHeart />
            <h3>A library that belongs to you.</h3>
            <p>
              Favorites, tags, albums, prompts, and seeds travel with your PNGs.
              Your pictures are files you can take anywhere.
            </p>
          </article>
        </div>
      </section>
      <section className="models" id={`${id}-models`}>
        <span className="eyebrow">THREE MODELS. ONE NATIVE WORKSPACE.</span>
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
        <span className="preview-label">
          Product page concept
          <br />
          Download coming later
        </span>
      </section>
      <footer>
        <Brand />
        <span>Local image generation. Made for Mac.</span>
      </footer>
    </>
  );
}
function Gallery() {
  return (
    <div className="gallery">
      <figure>
        <img
          src="/images/robot.png"
          alt="A weathered robot reading a newspaper in a sunlit park"
        />
        <figcaption>
          One prompt. <span>Room to explore.</span>
        </figcaption>
      </figure>
      <figure>
        <img
          src="/images/robot-chrome.png"
          alt="A polished chrome robot reading on a park bench"
        />
        <figcaption>A different interpretation.</figcaption>
      </figure>
      <figure>
        <img
          src="/images/robot-white.png"
          alt="A small white robot with headphones and a newspaper"
        />
        <figcaption>Another possibility.</figcaption>
      </figure>
    </div>
  );
}
export default function Page() {
  return (
    <Tabs defaultValue="Safelight" className="concepts">
      <div className="concept-bar">
        <span className="review-title">
          ZEPHRA <span>/ PRODUCT EXPLORATIONS</span>
        </span>
        <TabsList
          className="concept-picker"
          aria-label="Choose a product page concept"
        >
          {concepts.map((c, i) => (
            <TabsTrigger key={c} value={c}>
              {`0${i + 1}`} <span>{c}</span>
            </TabsTrigger>
          ))}
        </TabsList>
        <span className="review-note">Design preview · September 2026</span>
      </div>
      <TabsContent value="Safelight">
        <main className="safelight">
          <Nav id="dark" />
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
                your Mac. Powerful models. Native controls. Everything stays
                with you.
              </p>
              <a className="button" href="#dark-features">
                Explore Zephra <ArrowDown size={17} />
              </a>
              <span className="compatibility">
                Built for Apple Silicon · Powered by MLX
              </span>
            </div>
            <div className="hero-art">
              <img
                src="/images/robot.png"
                alt="An image of a curious robot enjoying a newspaper in the afternoon sun"
              />
              <div className="art-caption">
                <span>“A robot reading in the afternoon sun”</span>
                <span>FLUX.2 klein</span>
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
                Watch an image take shape with live previews. Keep ideas moving
                with a generation queue, and find your favorites in a searchable
                library.
              </p>
            </div>
            <img
              src="/images/app.png"
              alt="Zephra’s native macOS workspace showing live generation, a timeline, and an image inspector"
            />
            <small>Zephra app · Development screenshot</small>
          </section>
          <Features id="dark" />
        </main>
      </TabsContent>
      <TabsContent value="Native">
        <main className="native">
          <Nav id="native" />
          <section className="native-hero">
            <img
              className="hero-icon"
              src="/images/icon.png"
              alt="Zephra app icon"
            />
            <span className="eyebrow">IMAGINATION, MEET YOUR MAC.</span>
            <h1>
              Big ideas.
              <br />
              <span>Right at home.</span>
            </h1>
            <p>
              A native image studio for Apple Silicon.
              <br />
              Generate, edit, and organize. All on your Mac.
            </p>
            <a className="button" href="#native-features">
              Meet Zephra <ArrowDown size={17} />
            </a>
            <div className="native-app">
              <img
                src="/images/app.png"
                alt="Zephra on macOS with a live image preview and prompt controls"
              />
            </div>
          </section>
          <section className="native-gallery">
            <span className="eyebrow">THINK IT. SEE WHERE IT GOES.</span>
            <h2>One idea is just the beginning.</h2>
            <Gallery />
          </section>
          <Features id="native" />
        </main>
      </TabsContent>
      <TabsContent value="Atelier">
        <main className="atelier">
          <Nav id="atelier" />
          <section className="editorial-hero">
            <div className="editorial-title">
              <span className="eyebrow">AN IMAGE STUDIO, ON YOUR MAC.</span>
              <h1>
                Make room
                <br />
                for <em>imagining.</em>
              </h1>
              <div className="editorial-bottom">
                <p>
                  Follow a thought somewhere unexpected. Zephra puts local image
                  generation into a beautifully native Mac workspace.
                </p>
                <a
                  className="circle-link"
                  href="#atelier-features"
                  aria-label="Explore Zephra"
                >
                  <ArrowDown />
                </a>
              </div>
            </div>
            <figure>
              <img
                src="/images/robot-chrome.png"
                alt="A chrome robot lost in a newspaper under the trees"
              />
              <figcaption>FIG. 01 — AN AFTERNOON THAT NEVER WAS.</figcaption>
            </figure>
          </section>
          <div className="editorial-band">
            <span>Words become pictures.</span>
            <span>Pictures become possibilities.</span>
          </div>
          <section className="atelier-gallery">
            <div>
              <span className="eyebrow">THE ART OF ANOTHER TRY</span>
              <h2>
                Stay curious.
                <br />
                Keep creating.
              </h2>
            </div>
            <Gallery />
          </section>
          <Features id="atelier" />
        </main>
      </TabsContent>
    </Tabs>
  );
}
