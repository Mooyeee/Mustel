plugins {
    java
    id("org.jetbrains.intellij.platform") version "2.20.0"
}

group = "local.mustel"
version = "0.1.1"

val localIde = providers.gradleProperty("mustel.localIde").orNull

repositories {
    mavenCentral()
    intellijPlatform {
        defaultRepositories()
    }
}

dependencies {
    intellijPlatform {
        if (localIde != null) {
            local(localIde)
            providers.gradleProperty("mustel.flutterPlugin").orNull?.let { localPlugin(it) }
            providers.gradleProperty("mustel.dartPlugin").orNull?.let { localPlugin(it) }
            providers.gradleProperty("mustel.lsp4ijPlugin").orNull?.let { localPlugin(it) }
        } else {
            intellijIdeaCommunity("2023.1")
            compatiblePlugin("io.flutter")
            compatiblePlugin("Dart")
        }
        testFramework(org.jetbrains.intellij.platform.gradle.TestFrameworkType.Platform)
    }
    testImplementation("junit:junit:4.13.2")
}

java {
    toolchain {
        languageVersion.set(JavaLanguageVersion.of(if (localIde != null) 21 else 17))
    }
}

intellijPlatform {
    pluginConfiguration {
        ideaVersion {
            sinceBuild = "231"
            untilBuild = "261.*"
        }
    }
}
