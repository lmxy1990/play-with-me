#include <jni.h>

#include <cstdint>
#include <stdexcept>
#include <string>

struct SherpaOnnxOfflineTts;

struct SherpaOnnxOfflineTtsVitsModelConfig {
    const char *model;
    const char *lexicon;
    const char *tokens;
    const char *data_dir;
    float noise_scale;
    float noise_scale_w;
    float length_scale;
    const char *dict_dir;
};

struct SherpaOnnxOfflineTtsMatchaModelConfig {
    const char *acoustic_model;
    const char *vocoder;
    const char *lexicon;
    const char *tokens;
    const char *data_dir;
    float noise_scale;
    float length_scale;
    const char *dict_dir;
};

struct SherpaOnnxOfflineTtsKokoroModelConfig {
    const char *model;
    const char *voices;
    const char *tokens;
    const char *data_dir;
    float length_scale;
    const char *dict_dir;
    const char *lexicon;
    const char *lang;
};

struct SherpaOnnxOfflineTtsKittenModelConfig {
    const char *model;
    const char *voices;
    const char *tokens;
    const char *data_dir;
    float length_scale;
};

struct SherpaOnnxOfflineTtsZipVoiceModelConfig {
    const char *tokens;
    const char *encoder;
    const char *decoder;
    const char *vocoder;
    const char *data_dir;
    const char *lexicon;
    float feat_scale;
    float t_shift;
    float target_rms;
    float guidance_scale;
};

struct SherpaOnnxOfflineTtsPocketModelConfig {
    const char *lm_flow;
    const char *lm_main;
    const char *encoder;
    const char *decoder;
    const char *text_conditioner;
    const char *vocab_json;
    const char *token_scores_json;
    int32_t voice_embedding_cache_capacity;
};

struct SherpaOnnxOfflineTtsSupertonicModelConfig {
    const char *duration_predictor;
    const char *text_encoder;
    const char *vector_estimator;
    const char *vocoder;
    const char *tts_json;
    const char *unicode_indexer;
    const char *voice_style;
};

struct SherpaOnnxOfflineTtsModelConfig {
    SherpaOnnxOfflineTtsVitsModelConfig vits;
    int32_t num_threads;
    int32_t debug;
    const char *provider;
    SherpaOnnxOfflineTtsMatchaModelConfig matcha;
    SherpaOnnxOfflineTtsKokoroModelConfig kokoro;
    SherpaOnnxOfflineTtsKittenModelConfig kitten;
    SherpaOnnxOfflineTtsZipVoiceModelConfig zipvoice;
    SherpaOnnxOfflineTtsPocketModelConfig pocket;
    SherpaOnnxOfflineTtsSupertonicModelConfig supertonic;
};

struct SherpaOnnxOfflineTtsConfig {
    SherpaOnnxOfflineTtsModelConfig model;
    const char *rule_fsts;
    int32_t max_num_sentences;
    const char *rule_fars;
    float silence_scale;
};

struct SherpaOnnxGenerationConfig {
    float silence_scale;
    float speed;
    int32_t sid;
    const float *reference_audio;
    int32_t reference_audio_length;
    int32_t reference_sample_rate;
    const char *reference_text;
    int32_t num_steps;
    const char *extra;
};

struct SherpaOnnxGeneratedAudio {
    const float *samples;
    int32_t n;
    int32_t sample_rate;
};

extern "C" {
SherpaOnnxOfflineTts *SherpaOnnxCreateOfflineTts(const SherpaOnnxOfflineTtsConfig *config);
void SherpaOnnxDestroyOfflineTts(SherpaOnnxOfflineTts *tts);
const SherpaOnnxGeneratedAudio *SherpaOnnxOfflineTtsGenerateWithConfig(
    SherpaOnnxOfflineTts *tts,
    const char *text,
    const SherpaOnnxGenerationConfig *config,
    void *callback,
    void *callback_arg);
void SherpaOnnxDestroyOfflineTtsGeneratedAudio(const SherpaOnnxGeneratedAudio *audio);
int32_t SherpaOnnxWriteWave(
    const float *samples,
    int32_t n,
    int32_t sample_rate,
    const char *filename);
}

namespace {

class JniString {
public:
    JniString(JNIEnv *env, jstring value) : env_(env), value_(value) {
        chars_ = env_->GetStringUTFChars(value_, nullptr);
        if (chars_ == nullptr) {
            throw std::runtime_error("Unable to read Java string");
        }
    }

    ~JniString() {
        if (chars_ != nullptr) {
            env_->ReleaseStringUTFChars(value_, chars_);
        }
    }

    const char *c_str() const {
        return chars_;
    }

    std::string str() const {
        return std::string(chars_);
    }

private:
    JNIEnv *env_;
    jstring value_;
    const char *chars_ = nullptr;
};

void throw_java(JNIEnv *env, const char *message) {
    jclass error_class = env->FindClass("java/lang/IllegalStateException");
    if (error_class != nullptr) {
        env->ThrowNew(error_class, message);
    }
}

std::string join_path(const std::string &dir, const std::string &name) {
    if (dir.empty()) {
        return name;
    }
    if (dir.back() == '/') {
        return dir + name;
    }
    return dir + "/" + name;
}

}  // namespace

extern "C" JNIEXPORT jlong JNICALL
Java_com_playwithme_godot_KokoroNative_nativeCreate(
    JNIEnv *env,
    jclass,
    jstring model_dir,
    jint num_threads) {
    try {
        JniString dir_value(env, model_dir);
        const std::string dir = dir_value.str();
        const std::string empty;
        const std::string provider = "cpu";
        const std::string model = join_path(dir, "model.int8.onnx");
        const std::string voices = join_path(dir, "voices.bin");
        const std::string tokens = join_path(dir, "tokens.txt");
        const std::string data_dir = join_path(dir, "espeak-ng-data");
        const std::string lexicon =
            join_path(dir, "lexicon-us-en.txt") + "," +
            join_path(dir, "lexicon-gb-en.txt") + "," +
            join_path(dir, "lexicon-zh.txt");
        const std::string rule_fsts =
            join_path(dir, "phone-zh.fst") + "," +
            join_path(dir, "date-zh.fst") + "," +
            join_path(dir, "number-zh.fst");

        SherpaOnnxOfflineTtsConfig config{};
        config.model.vits.model = empty.c_str();
        config.model.vits.lexicon = empty.c_str();
        config.model.vits.tokens = empty.c_str();
        config.model.vits.data_dir = empty.c_str();
        config.model.vits.noise_scale = 0.667f;
        config.model.vits.noise_scale_w = 0.8f;
        config.model.vits.length_scale = 1.0f;
        config.model.vits.dict_dir = empty.c_str();

        config.model.matcha.acoustic_model = empty.c_str();
        config.model.matcha.vocoder = empty.c_str();
        config.model.matcha.lexicon = empty.c_str();
        config.model.matcha.tokens = empty.c_str();
        config.model.matcha.data_dir = empty.c_str();
        config.model.matcha.noise_scale = 0.667f;
        config.model.matcha.length_scale = 1.0f;
        config.model.matcha.dict_dir = empty.c_str();

        config.model.kokoro.model = model.c_str();
        config.model.kokoro.voices = voices.c_str();
        config.model.kokoro.tokens = tokens.c_str();
        config.model.kokoro.data_dir = data_dir.c_str();
        config.model.kokoro.length_scale = 1.0f;
        config.model.kokoro.dict_dir = empty.c_str();
        config.model.kokoro.lexicon = lexicon.c_str();
        config.model.kokoro.lang = empty.c_str();

        config.model.kitten.model = empty.c_str();
        config.model.kitten.voices = empty.c_str();
        config.model.kitten.tokens = empty.c_str();
        config.model.kitten.data_dir = empty.c_str();
        config.model.kitten.length_scale = 1.0f;

        config.model.zipvoice.tokens = empty.c_str();
        config.model.zipvoice.encoder = empty.c_str();
        config.model.zipvoice.decoder = empty.c_str();
        config.model.zipvoice.vocoder = empty.c_str();
        config.model.zipvoice.data_dir = empty.c_str();
        config.model.zipvoice.lexicon = empty.c_str();
        config.model.zipvoice.feat_scale = 0.1f;
        config.model.zipvoice.t_shift = 0.5f;
        config.model.zipvoice.target_rms = 0.1f;
        config.model.zipvoice.guidance_scale = 1.0f;

        config.model.pocket.lm_flow = empty.c_str();
        config.model.pocket.lm_main = empty.c_str();
        config.model.pocket.encoder = empty.c_str();
        config.model.pocket.decoder = empty.c_str();
        config.model.pocket.text_conditioner = empty.c_str();
        config.model.pocket.vocab_json = empty.c_str();
        config.model.pocket.token_scores_json = empty.c_str();
        config.model.pocket.voice_embedding_cache_capacity = 50;

        config.model.supertonic.duration_predictor = empty.c_str();
        config.model.supertonic.text_encoder = empty.c_str();
        config.model.supertonic.vector_estimator = empty.c_str();
        config.model.supertonic.vocoder = empty.c_str();
        config.model.supertonic.tts_json = empty.c_str();
        config.model.supertonic.unicode_indexer = empty.c_str();
        config.model.supertonic.voice_style = empty.c_str();

        config.model.num_threads = num_threads;
        config.model.debug = 0;
        config.model.provider = provider.c_str();
        config.rule_fsts = rule_fsts.c_str();
        config.max_num_sentences = 1;
        config.rule_fars = empty.c_str();
        config.silence_scale = 0.2f;

        SherpaOnnxOfflineTts *tts = SherpaOnnxCreateOfflineTts(&config);
        if (tts == nullptr) {
            throw std::runtime_error("Failed to create Sherpa Kokoro TTS runtime");
        }
        return reinterpret_cast<jlong>(tts);
    } catch (const std::exception &error) {
        throw_java(env, error.what());
        return 0;
    }
}

extern "C" JNIEXPORT void JNICALL
Java_com_playwithme_godot_KokoroNative_nativeDestroy(
    JNIEnv *,
    jclass,
    jlong handle) {
    auto *tts = reinterpret_cast<SherpaOnnxOfflineTts *>(handle);
    if (tts != nullptr) {
        SherpaOnnxDestroyOfflineTts(tts);
    }
}

extern "C" JNIEXPORT jintArray JNICALL
Java_com_playwithme_godot_KokoroNative_nativeGenerateToFile(
    JNIEnv *env,
    jclass,
    jlong handle,
    jstring text,
    jint sid,
    jfloat speed,
    jfloat silence_scale,
    jstring output_path) {
    try {
        auto *tts = reinterpret_cast<SherpaOnnxOfflineTts *>(handle);
        if (tts == nullptr) {
            throw std::runtime_error("Sherpa Kokoro runtime is not initialized");
        }
        JniString text_value(env, text);
        JniString path_value(env, output_path);

        SherpaOnnxGenerationConfig config{};
        config.silence_scale = silence_scale;
        config.speed = speed;
        config.sid = sid;
        config.reference_audio = nullptr;
        config.reference_audio_length = 0;
        config.reference_sample_rate = 0;
        config.reference_text = nullptr;
        config.num_steps = 5;
        config.extra = nullptr;

        const SherpaOnnxGeneratedAudio *audio = SherpaOnnxOfflineTtsGenerateWithConfig(
            tts,
            text_value.c_str(),
            &config,
            nullptr,
            nullptr);
        if (audio == nullptr || audio->samples == nullptr || audio->n <= 0 || audio->sample_rate <= 0) {
            if (audio != nullptr) {
                SherpaOnnxDestroyOfflineTtsGeneratedAudio(audio);
            }
            throw std::runtime_error("Sherpa Kokoro generated empty audio");
        }

        const int32_t ok = SherpaOnnxWriteWave(
            audio->samples,
            audio->n,
            audio->sample_rate,
            path_value.c_str());
        const jint result_values[2] = {audio->sample_rate, audio->n};
        SherpaOnnxDestroyOfflineTtsGeneratedAudio(audio);

        if (ok != 1) {
            throw std::runtime_error("Unable to write Kokoro wave file");
        }

        jintArray result = env->NewIntArray(2);
        if (result == nullptr) {
            throw std::runtime_error("Unable to allocate JNI result");
        }
        env->SetIntArrayRegion(result, 0, 2, result_values);
        return result;
    } catch (const std::exception &error) {
        throw_java(env, error.what());
        return nullptr;
    }
}
