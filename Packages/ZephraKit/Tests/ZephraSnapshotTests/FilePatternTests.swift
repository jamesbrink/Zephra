import Testing
import ZephraSnapshot

@Suite("The globs a catalog entry filters a repository with")
struct FilePatternTests {
    @Test("a star crosses directories, the way the hub's own matching does")
    func starCrossesDirectories() {
        #expect(FilePattern.matches("transformer/config.json", pattern: "*.json"))
        #expect(FilePattern.matches("model_index.json", pattern: "*.json"))
        #expect(!FilePattern.matches("vae/model.safetensors", pattern: "*.json"))
    }

    @Test("a directory pattern takes everything under it, however deep")
    func directoryPatternTakesTheSubtree() {
        #expect(FilePattern.matches("tokenizer/tokenizer.json", pattern: "tokenizer/*"))
        #expect(FilePattern.matches("tokenizer/extra/merges.txt", pattern: "tokenizer/*"))
        #expect(!FilePattern.matches("text_encoder/config.json", pattern: "tokenizer/*"))
    }

    @Test("a question mark stands for exactly one character")
    func questionMarkIsOneCharacter() {
        #expect(FilePattern.matches("model-00001-of-00002.safetensors", pattern: "model-?????-of-*"))
        #expect(!FilePattern.matches("model-1-of-2.safetensors", pattern: "model-?????-of-*"))
    }

    @Test("a name with no wildcard in it matches only itself")
    func literalMatchesItself() {
        #expect(FilePattern.matches("flux-2-klein-4b.safetensors", pattern: "flux-2-klein-4b.safetensors"))
        #expect(!FilePattern.matches("flux-2-klein-4b.safetensors.index.json", pattern: "flux-2-klein-4b.safetensors"))
    }

    @Test("the catalog's own patterns take the weights and leave the sample images")
    func catalogPatternsSelectWhatIsWanted() {
        let patterns = ["*.safetensors", "*.json", "tokenizer/*"]
        for wanted in [
            "model_index.json", "transformer/config.json",
            "transformer/diffusion_pytorch_model.safetensors", "tokenizer/tokenizer_config.json",
        ] {
            #expect(FilePattern.matchesAny(wanted, patterns: patterns), "\(wanted) is weights")
        }
        for unwanted in ["assets/sample.png", "README.md", "assets/grid.jpg"] {
            #expect(!FilePattern.matchesAny(unwanted, patterns: patterns), "\(unwanted) is not")
        }
    }

    @Test("no patterns at all takes the repository whole")
    func noPatternsTakesEverything() {
        #expect(FilePattern.matchesAny("anything/at/all.bin", patterns: []))
    }
}
