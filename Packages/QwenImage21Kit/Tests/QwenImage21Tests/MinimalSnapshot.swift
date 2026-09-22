import Foundation
import ZephraTestSupport

/// The smallest snapshot `QwenImage21Configuration` will read, written into a scratch folder.
///
/// It exists so the decoding rules are covered on a Mac with no 33 GB release on it: the field
/// names, the nesting, the validations and the two cross-file invariants are all exercised
/// here, and the suite that reads the real configs checks that the published numbers are the
/// ones the port expects.
enum MinimalSnapshot {
    /// Writes a snapshot under `scratch` and answers its root. Each argument replaces one
    /// file, so a test can make exactly one thing wrong.
    @discardableResult
    static func write(
        into scratch: Scratch,
        transformer: String = transformerJSON,
        vae: String = vaeJSON,
        textEncoder: String = textEncoderJSON,
        scheduler: String = schedulerJSON,
        processor: String = processorJSON,
        modelIndex: String? = modelIndexJSON
    ) throws -> URL {
        try scratch.write(transformer, to: "snapshot/transformer/config.json")
        try scratch.write(vae, to: "snapshot/vae/config.json")
        try scratch.write(textEncoder, to: "snapshot/text_encoder/config.json")
        try scratch.write(scheduler, to: "snapshot/scheduler/scheduler_config.json")
        try scratch.write(processor, to: "snapshot/processor/preprocessor_config.json")
        if let modelIndex {
            try scratch.write(modelIndex, to: "snapshot/model_index.json")
        }
        return scratch.root.appending(path: "snapshot")
    }

    /// A doll's house: two heads of sixteen, three rope axes filling one head, eight latent
    /// channels. The published shape at a size that reads in one screen.
    static let transformerJSON = """
        {"_class_name": "QwenImage21Transformer2DModel", "attention_head_dim": 16,
         "axes_dims_rope": [4, 6, 6], "context_in_dim": 32, "in_channels": 8,
         "num_attention_heads": 2, "num_layers": 2, "out_channels": 8, "patch_size": 1,
         "mlp_ratio": 3, "eps": 1e-06, "causal_condition": true}
        """

    static let vaeJSON = """
        {"_class_name": "AutoencoderKLQwenImage21", "attn_scales": [], "base_dim": 8,
         "decoder_base_dim": 12, "z_dim": 8, "dim_mult": [1, 2], "num_res_blocks": 1,
         "temperal_downsample": [false], "dropout": 0.0, "is_residual": true,
         "in_channels": 4, "out_channels": 4, "patch_size": null,
         "scale_factor_spatial": 16, "scale_factor_temporal": 8,
         "latents_mean": [0.1, -0.2, 0.3, -0.4, 0.5, -0.6, 0.7, -0.8],
         "latents_std": [1.1, 1.2, 1.3, 1.4, 1.5, 1.6, 1.7, 1.8]}
        """

    static let textEncoderJSON = """
        {"architectures": ["Qwen3VLForConditionalGeneration"], "model_type": "qwen3_vl",
         "image_token_id": 151655, "video_token_id": 151656,
         "vision_start_token_id": 151652, "vision_end_token_id": 151653,
         "tie_word_embeddings": false,
         "text_config": {"hidden_size": 32, "intermediate_size": 96, "num_hidden_layers": 2,
           "num_attention_heads": 4, "num_key_value_heads": 1, "head_dim": 8,
           "rms_norm_eps": 1e-06, "rope_theta": 5000000, "vocab_size": 64,
           "hidden_act": "silu", "attention_bias": false,
           "rope_scaling": {"mrope_interleaved": true, "mrope_section": [2, 1, 1],
             "rope_type": "default"}},
         "vision_config": {"depth": 4, "hidden_size": 32, "num_heads": 2,
           "intermediate_size": 64, "in_channels": 3, "patch_size": 4,
           "temporal_patch_size": 2, "spatial_merge_size": 2,
           "num_position_embeddings": 64, "out_hidden_size": 32,
           "deepstack_visual_indexes": [1, 3], "hidden_act": "gelu_pytorch_tanh"}}
        """

    /// The published scheduler settings verbatim; nothing about them is doll's-house sized.
    static let schedulerJSON = """
        {"_class_name": "FlowMatchEulerDiscreteScheduler", "base_image_seq_len": 256,
         "base_shift": 0.5, "invert_sigmas": false, "max_image_seq_len": 8192,
         "max_shift": 0.9, "num_train_timesteps": 1000, "shift": 1.0,
         "shift_terminal": 0.02, "stochastic_sampling": false,
         "time_shift_type": "exponential", "use_beta_sigmas": false,
         "use_dynamic_shifting": true, "use_exponential_sigmas": false,
         "use_karras_sigmas": false}
        """

    static let processorJSON = """
        {"image_processor_type": "Qwen2VLImageProcessorFast", "processor_class": "Qwen3VLProcessor",
         "image_mean": [0.5, 0.5, 0.5], "image_std": [0.5, 0.5, 0.5], "merge_size": 2,
         "patch_size": 4, "temporal_patch_size": 2, "resample": 3,
         "rescale_factor": 0.00392156862745098,
         "size": {"longest_edge": 16777216, "shortest_edge": 65536}}
        """

    static let modelIndexJSON = """
        {"_class_name": "QwenImage21Pipeline", "_diffusers_version": "0.37.0.dev0",
         "processor": ["transformers", "Qwen3VLProcessor"],
         "scheduler": ["diffusers", "FlowMatchEulerDiscreteScheduler"],
         "text_encoder": ["transformers", "Qwen3VLForConditionalGeneration"],
         "transformer": ["diffusers", "QwenImage21Transformer2DModel"],
         "vae": ["diffusers", "AutoencoderKLQwenImage21"]}
        """
}
