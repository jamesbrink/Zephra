extension BenchOptions {
    static let usage = """
        usage: ZephraBench [--model ID] [--models DIR] [--size N|WxH] [--steps N] [--frames N] [--runs N] \
        [--prompt TEXT] [--out PATH] [--json] [--micro] [--preview] \
        [--backend NAME --snapshot DIR] [--reference IMAGE --strength S] \
        [--extend CLIP.mp4 [--context N]] [--stream [--stream-depth N]]

        --model names a catalog entry, so variants can be compared at a fixed seed.
        --models names the folder the models live in and download into; without it the
        app's default folder is used, so pass the one Settings > Models names (the
        Makefile passes MODELS_DIR) or a run may download a model the app already has.
        --size is one number for a square picture or WxH for anything else; a video model
        takes the same flag for its frame size. --frames is the clip's length on a model that
        makes one (rounded down to the model's ladder, 8k + 1 for LTX-2.5, 4k + 1 for Wan 2.2);
        a picture model
        ignores it. A clip is written to --out with its extension changed to .mp4, and its
        first frame as a PNG beside it.
        --backend and --snapshot together run a model the catalog does not carry yet, which
        is how a new family is measured before its entry can be written.
        --reference takes any picture macOS can read and measures the editing path on a
        model that has one; the picture's own pixels add tokens, so its size is part of what
        is being measured. On LTX-2.5 and Wan 2.2 it is the clip's first frame instead, and
        the picture is scaled to cover the clip and cropped to the middle.
        --strength (0 to 1, default 0.6) says how much of that picture to throw away, and
        what a model does with it depends on how it reads a picture. One that starts from a
        noised copy buys that share of the steps, truncated and never fewer than one, so 0.6
        of nine steps runs five and small values keep most of the picture; it clamps the
        flag into its own bounds (0.1 to 0.9), so 0 and 1 are never what runs. FLUX.2 klein
        conditions on the picture directly, pins it at 1 and ignores it. LTX-2.5 holds the
        picture as the clip's first frame and reads the flag the other way round, as 1 minus
        how strongly to hold it: 0, its default, holds the frame exactly, its bound of 0.9
        barely holds it at all, and the whole ladder runs either way. Wan 2.2 holds the
        frame exactly and ignores the flag. The report, not this flag, says the strength
        that ran and the step it began at.
        --extend takes a clip and measures carrying it on: its last frames (--context of
        them, else the model's own default, 9 on LTX-2.5 and 1 on Wan 2.2) are held at the
        head of the run as the app's Extend Clip holds them, and the run is joined onto the
        clip as <stem>-extended.mp4 beside --out, the held frames dropped at the join.
        --preview turns on the live preview frames the app shows while a run is going and
        reports what they cost: how many were made and the mean milliseconds one took. The
        last frame is written beside --out as <stem>.preview.png, because a frame unpacked on
        the wrong axis is noise of exactly the right size. Frames are off without this flag,
        so a step time measured without it is the model's own.
        --micro times the DiT's individual MLX kernels at --size worth of tokens and
        exits, without loading any weights; it follows --model, and only Z-Image has one,
        so any other family is refused rather than timed under the wrong name.
        
        --stream reads the weights from disk on every step instead of holding them, the way
        the app does on a Mac whose GPU cannot hold the model, and reports the bytes read per
        step and the disk's rate; --stream-depth is how many blocks are read ahead (2 unless
        set). A model whose family cannot stream loads resident whatever the flag says.
"""
}
