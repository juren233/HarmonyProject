-keep class com.ding.rtc.** { *; }
-keep class org.webrtc.mozi.** { *; }
-keep class org.webrtc.** { *; }
-keep class com.aliyun.** { *; }
-keep class com.alivc.** { *; }

-keepclassmembers class * {
    native <methods>;
}
