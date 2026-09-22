import release from './release.json';
import { latestManifestURL } from './download';

const models = [
  {
    name: 'FLUX.2 klein 4B',
    size: '5.4 GB',
    setup: '21.4 GB',
    use: 'A smaller starting point for images.',
  },
  {
    name: 'Z-Image-Turbo',
    size: '7.1 GB',
    setup: '40.0 GB',
    use: 'Another way to explore still images.',
  },
  {
    name: 'Qwen-Image 2.1',
    size: '11.6 GB',
    setup: '44.7 GB',
    use: 'Images with legible text, and edits from up to ten reference pictures. Research license, non-commercial use only.',
  },
  {
    name: 'Wan 2.2 TI2V-5B',
    size: '10.1 GB',
    setup: '34.3 GB',
    use: 'Silent video from text or a first frame.',
  },
  {
    name: 'LTX-2.5 · video only',
    size: '20.8 GB',
    setup: '91.5 GB',
    use: 'Short videos and image animation.',
  },
  {
    name: 'LTX-2.5 · with sound',
    size: '25.8 GB',
    setup: '96.8 GB',
    use: 'Generate video and audio together.',
  },
];

export default function GettingStarted({ id }: { id: string }) {
  return (
    <>
      <section
        className="getting-started content-section"
        aria-labelledby="start-heading"
      >
        <span className="eyebrow">FROM DOWNLOAD TO FIRST IDEA</span>
        <h2 id="start-heading">Make yourself at home.</h2>
        <ol className="setup-steps">
          <li>
            <span className="step-number">01</span>
            <h3>Install Zephra</h3>
            <p>
              Open the download, drag Zephra into Applications, and launch it
              from there.
            </p>
          </li>
          <li>
            <span className="step-number">02</span>
            <h3>Choose a model</h3>
            <p>
              Pick a model for images or video. Its first use needs an internet
              connection to download the model and space on your Mac to prepare
              it.
            </p>
          </li>
          <li>
            <span className="step-number">03</span>
            <h3>Follow your imagination</h3>
            <p>
              Write a prompt and select Generate. Once your model is ready, you
              can create offline. Your work goes into your local library.
            </p>
          </li>
        </ol>
      </section>
      <section
        className="mac-guide content-section"
        id={`${id}-requirements`}
        aria-labelledby="mac-heading"
      >
        <span className="eyebrow">MADE FOR APPLE SILICON</span>
        <h2 id="mac-heading">Will it run on my Mac?</h2>
        <p className="section-lead">
          You’ll need a Mac with an Apple M-series chip and macOS 15 or later.
          Intel Macs aren’t supported.
        </p>
        <div className="memory-guide">
          <div>
            <h3>Start with the right model.</h3>
            <p>
              FLUX.2 klein 4B at 4-bit is the smallest image model here. It’s a
              good place to start on a 16 GB Mac. Larger images and reference
              edits can need more memory.
            </p>
          </div>
          <div>
            <h3>Make room for motion.</h3>
            <p>
              Wan 2.2 and both LTX-2.5 variants can stream weights from disk.
              Choose streaming in Settings → Performance to reduce memory use. A
              fast SSD helps; generation can take longer than keeping the model
              in memory. The audio variant needs more memory than video alone.
            </p>
          </div>
        </div>
        <h3 className="storage-heading">Leave room for your models.</h3>
        <div className="model-storage">
          {models.map((model) => (
            <article key={model.name}>
              <h4>{model.name}</h4>
              <p>{model.use}</p>
              <dl>
                <div>
                  <dt>Prepared model</dt>
                  <dd>{model.size}</dd>
                </div>
                <div>
                  <dt>With source files</dt>
                  <dd>{model.setup}</dd>
                </div>
              </dl>
            </article>
          ))}
        </div>
        <p className="guide-note">
          Approximate disk sizes for 4-bit models, not RAM requirements. Zephra
          downloads a prepared model when available. Otherwise, it downloads the
          source and builds it locally, keeping both copies. Allow additional
          free space for setup, macOS, and your library.
        </p>
        <details className="memory-details">
          <summary>How much memory does generation use?</summary>
          <p>
            Recorded image-generation peaks at 1024 × 1024 with tiled decoding:
            FLUX.2 klein 4-bit, about 7.7 GB; Z-Image-Turbo 4-bit, 12.0 GB.
          </p>
          <p>
            Wan 2.2 at 832 × 480 and 49 frames measured about 15.1 GB, 12.4 GB
            with tiled decoding, or 9.7 GB with streaming. LTX-2.5 at 768 × 512
            and 49 frames measured about 23.4 GB with resident weights, or 10.0
            GB with streaming. Its “with sound” variant measured 28.7 GB
            resident or 12.1 GB streamed. These are measured workload figures,
            not minimum Mac memory requirements. Leave memory for macOS and
            other apps; resolution, clip length, and settings affect usage.
          </p>
        </details>
      </section>
      <section
        className="release-notes content-section"
        id="whats-new"
        aria-labelledby="release-heading"
      >
        <span className="eyebrow">WHAT’S NEW</span>
        <h2 id="release-heading">More ways to make it yours.</h2>
        <p className="release-version">
          Version {release.version} · The download is always the newest build;{' '}
          <a href={latestManifestURL}>latest.json</a> names it and its SHA-256.
        </p>
        <ul>
          <li>
            <strong>Video with sound.</strong> Choose LTX-2.5’s “with sound”
            variant to generate audio and video together, saved in one MP4.
          </li>
          <li>
            <strong>Meet Wan 2.2.</strong> Generate silent clips from a prompt
            or animate a picture with the TI2V-5B model.
          </li>
          <li>
            <strong>More control over memory.</strong> Stream Qwen-Image 2.1,
            Wan 2.2, and LTX-2.5 weights from disk in Settings → Performance.
          </li>
        </ul>
      </section>
    </>
  );
}
