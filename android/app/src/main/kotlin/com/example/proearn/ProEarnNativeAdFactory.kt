package com.example.proearn

import android.graphics.Color
import android.graphics.Typeface
import android.view.Gravity
import android.view.View
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView
import com.google.android.gms.ads.nativead.MediaView
import com.google.android.gms.ads.nativead.NativeAd
import com.google.android.gms.ads.nativead.NativeAdView
import io.flutter.plugins.googlemobileads.GoogleMobileAdsPlugin.NativeAdFactory

class ProEarnNativeAdFactory(private val context: android.content.Context) : NativeAdFactory {
    override fun createNativeAd(
        nativeAd: NativeAd,
        customOptions: Map<String, Any>?
    ): NativeAdView {
        val density = context.resources.displayMetrics.density
        fun dp(value: Int) = (value * density).toInt()

        val adView = NativeAdView(context)
        val root = LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(12), dp(12), dp(12), dp(12))
            setBackgroundColor(Color.rgb(30, 30, 30))
        }

        val sponsored = TextView(context).apply {
            text = "Sponsored"
            textSize = 11f
            setTextColor(Color.LTGRAY)
        }
        root.addView(sponsored)

        val header = LinearLayout(context).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(0, dp(8), 0, dp(8))
        }
        val icon = ImageView(context)
        header.addView(icon, LinearLayout.LayoutParams(dp(40), dp(40)))
        val title = TextView(context).apply {
            textSize = 16f
            typeface = Typeface.DEFAULT_BOLD
            setTextColor(Color.WHITE)
            setPadding(dp(10), 0, 0, 0)
        }
        header.addView(title, LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f))
        root.addView(header)

        val media = MediaView(context)
        root.addView(media, LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT, dp(150)
        ))

        val body = TextView(context).apply {
            textSize = 13f
            setTextColor(Color.LTGRAY)
            setPadding(0, dp(8), 0, dp(8))
        }
        root.addView(body)

        val cta = TextView(context).apply {
            textSize = 14f
            typeface = Typeface.DEFAULT_BOLD
            setTextColor(Color.WHITE)
            gravity = Gravity.CENTER
            setPadding(dp(14), dp(10), dp(14), dp(10))
            setBackgroundColor(Color.rgb(35, 115, 220))
        }
        root.addView(cta, LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT
        ))

        adView.addView(root)
        adView.headlineView = title
        adView.iconView = icon
        adView.mediaView = media
        adView.bodyView = body
        adView.callToActionView = cta

        title.text = nativeAd.headline
        nativeAd.icon?.let {
            icon.setImageDrawable(it.drawable)
            icon.visibility = View.VISIBLE
        } ?: run { icon.visibility = View.GONE }
        nativeAd.mediaContent?.let { media.mediaContent = it }
        nativeAd.body?.let {
            body.text = it
            body.visibility = View.VISIBLE
        } ?: run { body.visibility = View.GONE }
        nativeAd.callToAction?.let {
            cta.text = it
            cta.visibility = View.VISIBLE
        } ?: run { cta.visibility = View.GONE }

        adView.setNativeAd(nativeAd)
        return adView
    }
}
