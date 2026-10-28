import org.jetbrains.kotlin.gradle.dsl.JvmTarget
plugins { id("com.android.application"); id("org.jetbrains.kotlin.android") }
val releaseKeystore = providers.environmentVariable("VAANI_ANDROID_KEYSTORE").orNull
val releaseVersion = providers.environmentVariable("VAANI_VERSION").orElse("0.1.0").get()
val releaseVersionCode = providers.environmentVariable("VAANI_VERSION_CODE").orElse("1").get().toInt()
android {
    namespace = "dev.vaani.keyboard"
    compileSdk = 36
    defaultConfig {
        applicationId = "dev.vaani.keyboard"
        minSdk = 28
        targetSdk = 36
        versionCode = releaseVersionCode
        versionName = releaseVersion
        testInstrumentationRunner = "dev.vaani.keyboard.DeviceSmokeRunner"
    }
    compileOptions { sourceCompatibility = JavaVersion.VERSION_17; targetCompatibility = JavaVersion.VERSION_17 }
    signingConfigs {
        if (releaseKeystore != null) create("release") {
            storeFile = file(releaseKeystore)
            storePassword = providers.environmentVariable("VAANI_ANDROID_KEYSTORE_PASSWORD").get()
            keyAlias = providers.environmentVariable("VAANI_ANDROID_KEY_ALIAS").get()
            keyPassword = providers.environmentVariable("VAANI_ANDROID_KEY_PASSWORD").get()
        }
    }
    buildTypes {
        getByName("release") {
            if (releaseKeystore != null) signingConfig = signingConfigs.getByName("release")
        }
    }
}
kotlin { compilerOptions { jvmTarget = JvmTarget.JVM_17 } }
dependencies {
    implementation("com.squareup.okhttp3:okhttp:4.12.0")
    testImplementation("junit:junit:4.13.2")
    testImplementation("org.json:json:20240303")
}
