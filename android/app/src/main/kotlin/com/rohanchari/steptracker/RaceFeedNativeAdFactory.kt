package com.rohanchari.steptracker

import android.content.Context
import android.graphics.Color
import android.graphics.Typeface
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.widget.LinearLayout
import android.widget.TextView
import com.google.android.gms.ads.nativead.MediaView
import com.google.android.gms.ads.nativead.NativeAd
import com.google.android.gms.ads.nativead.NativeAdView
import io.flutter.plugins.googlemobileads.NativeAdFactory

/** The shared Flutter placement reserves 144dp: 120dp media plus 12dp insets. */
class RaceFeedNativeAdFactory(private val context: Context) : NativeAdFactory {
    private fun dp(value: Int) = (value * context.resources.displayMetrics.density).toInt()

    override fun createNativeAd(nativeAd: NativeAd, customOptions: MutableMap<String, Any>?): NativeAdView {
        val view = NativeAdView(context)
        val row = LinearLayout(context).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(12), dp(12), dp(12), dp(12))
            setBackgroundColor(Color.rgb(255, 251, 245))
        }
        view.addView(row, ViewGroup.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dp(144)))
        val media = MediaView(context)
        row.addView(media, LinearLayout.LayoutParams(dp(120), dp(120)))
        view.mediaView = media
        nativeAd.mediaContent?.let { media.mediaContent = it }

        val details = LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(10), 0, dp(20), 0) // Reserve the SDK's AdChoices corner.
        }
        row.addView(details, LinearLayout.LayoutParams(0, dp(120), 1f))
        fun text(value: String?, size: Float, lines: Int): TextView = TextView(context).apply {
            text = value
            textSize = size
            maxLines = lines
            ellipsize = android.text.TextUtils.TruncateAt.END
            setTextColor(Color.rgb(48, 42, 35))
            includeFontPadding = false
            if (value.isNullOrBlank()) visibility = View.GONE
        }
        details.addView(text("AD", 10f, 1).apply {
            setTypeface(typeface, Typeface.BOLD)
            setPadding(0, 0, 0, dp(4))
        })
        val headline = text(nativeAd.headline, 14f, 2).apply { setTypeface(typeface, Typeface.BOLD) }
        details.addView(headline)
        view.headlineView = headline
        val body = text(nativeAd.body, 11f, 2).apply { setPadding(0, dp(3), 0, dp(3)) }
        details.addView(body)
        view.bodyView = body
        val cta = text(nativeAd.callToAction, 12f, 1).apply {
            setTypeface(typeface, Typeface.BOLD)
            setTextColor(Color.rgb(36, 83, 48))
            setPadding(0, dp(4), 0, dp(4))
        }
        details.addView(cta)
        view.callToActionView = cta
        view.setNativeAd(nativeAd)
        return view
    }
}
