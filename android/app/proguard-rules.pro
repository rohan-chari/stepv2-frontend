# OkHttp detects these alternative TLS providers at runtime when an app
# explicitly installs one. Bara does not bundle them, so their absent classes
# are expected and safe for R8 to ignore. Liftoff/Vungle brings OkHttp into the
# release graph.
-dontwarn org.bouncycastle.jsse.**
-dontwarn org.conscrypt.**
-dontwarn org.openjsse.**
