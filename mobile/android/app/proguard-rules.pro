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
