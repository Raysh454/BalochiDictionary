# jsoup is reached only from the widget providers, which R8 sees through the
# manifest. Keeping it explicitly means a future shrinker change cannot quietly
# strip the parser and turn every Rekhta fetch into a caught exception, which
# surfaces to the user as an unexplained "no connection".
-keep class org.jsoup.** { *; }
-dontwarn org.jsoup.**

# jsoup is a multi-release jar; its Java 9+ helpers are absent on Android and
# are never referenced there.
-dontwarn java.net.http.**
-dontwarn org.jspecify.annotations.**

# WorkManager instantiates workers reflectively from the class name it stored
# in its database, so an obfuscated or stripped worker fails at runtime with a
# ClassNotFoundException long after the code looked fine at build time.
-keep public class * extends androidx.work.ListenableWorker {
    public <init>(android.content.Context, androidx.work.WorkerParameters);
}
