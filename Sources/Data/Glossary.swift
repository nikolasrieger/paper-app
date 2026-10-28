import Foundation

struct GlossaryEntry: Identifiable, Hashable, Codable {
    var id: String { term.lowercased().replacingOccurrences(of: " ", with: "-") }
    let term: String
    var aliases: [String] = []
    let definition: String
    var formula: String? = nil   // optional LaTeX

    var allForms: [String] { ([term] + aliases).sorted { $0.count > $1.count } }

    enum CodingKeys: String, CodingKey { case term, aliases, definition, formula }

    init(term: String, aliases: [String] = [], definition: String, formula: String? = nil) {
        self.term = term; self.aliases = aliases; self.definition = definition; self.formula = formula
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        term = try c.decode(String.self, forKey: .term)
        aliases = try c.decodeIfPresent([String].self, forKey: .aliases) ?? []
        definition = try c.decode(String.self, forKey: .definition)
        formula = try c.decodeIfPresent(String.self, forKey: .formula)
    }
}

/// Terms that become tappable inside summaries. To add one, append an entry.
enum Glossary {
    /// Terms contributed by synced papers; the built-in list wins on a clash.
    static var extra: [GlossaryEntry] = []

    static var entries: [GlossaryEntry] {
        let known = Set(base.map(\.id))
        return base + extra.filter { !known.contains($0.id) }
    }

    static func entry(id: String) -> GlossaryEntry? { entries.first { $0.id == id } }

    static let base: [GlossaryEntry] = [
        .init(term: "self-attention", aliases: ["attention"],
              definition: "A mechanism in which every position in a sequence computes a weighted average over all positions, with weights given by the similarity of learned query and key vectors.",
              formula: #"\text{softmax}\left(\frac{QK^{\top}}{\sqrt{d_k}}\right)V"#),
        .init(term: "softmax",
              definition: "Turns a vector of real numbers into a probability distribution by exponentiating and normalising.",
              formula: #"\text{softmax}(z)_i=\frac{e^{z_i}}{\sum_j e^{z_j}}"#),
        .init(term: "recurrence", aliases: ["RNN", "RNNs", "LSTM"],
              definition: "Processing a sequence step by step while carrying a hidden state, so that each step depends on the previous one. This prevents parallelism across positions."),
        .init(term: "residual connection", aliases: ["residual", "residuals"],
              definition: "Adds a layer's input to its output, so the layer learns a correction. This keeps gradients flowing in deep networks.",
              formula: #"y=x+F(x)"#),
        .init(term: "LayerNorm", aliases: ["layer normalisation", "layer normalization"],
              definition: "Normalises the activations of one example across its feature dimension to zero mean and unit variance, then applies a learned scale and shift."),
        .init(term: "positional encoding", aliases: ["positional encodings", "position embedding"],
              definition: "A vector added to each token embedding to tell an order-agnostic model where the token sits in the sequence."),
        .init(term: "BLEU",
              definition: "A machine-translation metric based on n-gram overlap between a system output and reference translations. Higher is better."),
        .init(term: "beam search",
              definition: "A decoding algorithm that keeps the k highest-scoring partial sequences at each step instead of only the single best one."),
        .init(term: "greedy decoding", aliases: ["greedy"],
              definition: "Always choosing the single most probable next token, without exploring alternatives."),
        .init(term: "label smoothing",
              definition: "Replaces one-hot training targets with slightly softened ones, which regularises the model and typically improves calibration and BLEU."),
        .init(term: "dropout",
              definition: "A regulariser that randomly zeroes a fraction of activations during training."),
        .init(term: "autoregressive", aliases: ["autoregression", "left-to-right"],
              definition: "Generating a sequence one token at a time, each conditioned on the tokens before it.",
              formula: #"P(x)=\prod_t P(x_t\mid x_{<t})"#),
        .init(term: "BPE", aliases: ["byte-pair encoding"],
              definition: "Byte-pair encoding: a subword tokenisation that repeatedly merges the most frequent adjacent symbol pairs into new vocabulary items."),
        .init(term: "WordPiece",
              definition: "A subword tokenisation similar to BPE that builds its vocabulary by maximising training-data likelihood. Used by BERT."),
        .init(term: "pre-training", aliases: ["pre-trained", "pre-train"],
              definition: "Training a model on a large generic corpus with a self-supervised objective before adapting it to specific tasks."),
        .init(term: "fine-tuning", aliases: ["fine-tuned", "finetuned", "finetuning", "finetune", "fine-tune"],
              definition: "Continuing to train a pre-trained model on a smaller task-specific dataset, updating its weights."),
        .init(term: "masked language model", aliases: ["MLM", "masked language modelling", "masked-LM", "masked LM"],
              definition: "A pre-training objective where some input tokens are hidden and the model predicts them from the surrounding context on both sides."),
        .init(term: "NLI", aliases: ["natural language inference"],
              definition: "Natural language inference: deciding whether one sentence entails, contradicts or is neutral to another."),
        .init(term: "GLUE",
              definition: "A benchmark suite of nine sentence-level language-understanding tasks, reported as an average score."),
        .init(term: "SQuAD",
              definition: "The Stanford Question Answering Dataset: questions about Wikipedia passages where the answer is a span of the passage."),
        .init(term: "few-shot", aliases: ["few-shot prompting", "one-shot", "zero-shot"],
              definition: "Solving a task given a handful of demonstrations (few-shot), one (one-shot) or none (zero-shot) in the prompt, with no weight updates."),
        .init(term: "in-context learning",
              definition: "A model adapting to a task purely from examples and instructions placed in its context window, without gradient updates."),
        .init(term: "scaling law", aliases: ["scaling laws", "power law", "power-law"],
              definition: "An empirical relationship, usually a power law, between loss and model size, data or compute.",
              formula: #"L(C)\approx\left(\frac{C_c}{C}\right)^{\alpha}"#),
        .init(term: "cross-entropy", aliases: ["cross-entropy loss"],
              definition: "The standard classification loss: the negative log-probability a model assigns to the correct answer.",
              formula: #"\mathcal{L}=-\log P(y\mid x)"#),
        .init(term: "ablation", aliases: ["ablations"],
              definition: "An experiment that removes or replaces one component of a system to measure how much it contributes."),
        .init(term: "emergent", aliases: ["emerge", "emerges", "emergent ability"],
              definition: "A capability that is absent in small models and appears abruptly beyond a certain scale."),
        .init(term: "verifier",
              definition: "A separate model that scores candidate solutions so the best one can be selected."),
        .init(term: "RLHF", aliases: ["reinforcement learning from human feedback"],
              definition: "Reinforcement learning from human feedback: train a reward model on human preference comparisons, then optimise the policy against it."),
        .init(term: "RLAIF", aliases: ["RL from AI feedback", "AI feedback"],
              definition: "Like RLHF, but the preference labels come from an AI model instead of humans."),
        .init(term: "PPO",
              definition: "Proximal policy optimisation: a policy-gradient RL algorithm that limits each update to stay close to the previous policy."),
        .init(term: "preference model", aliases: ["reward model"],
              definition: "A model trained to score responses so that preferred responses get higher scores. Used as the reward signal in RLHF."),
        .init(term: "red-team", aliases: ["red team", "red-teaming"],
              definition: "Deliberately probing a model with adversarial prompts to find harmful or unwanted behaviour."),
        .init(term: "Elo",
              definition: "A rating system that turns pairwise comparison results into a single score per competitor."),
        .init(term: "Pareto", aliases: ["Pareto-improvement"],
              definition: "A Pareto improvement is better on one objective without being worse on another, here harmlessness versus helpfulness."),
        .init(term: "jailbreak", aliases: ["jailbreaks"],
              definition: "A prompt crafted to make a model ignore its safety training."),
    ]
}
