package com.rohanchari.steptracker

import android.view.View
import android.widget.TextView
import com.google.android.gms.ads.nativead.NativeAd
import com.google.android.gms.ads.nativead.NativeAdView
import com.google.android.gms.ads.nativead.MediaView
import com.google.android.gms.common.GooglePlayServicesUtilLight
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.mockito.Mockito.*
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config
import org.robolectric.annotation.Implements
import org.robolectric.annotation.Implementation

@Implements(NativeAdView::class)
class NativeAdBindingShadow : org.robolectric.shadows.ShadowViewGroup() {
    companion object { var boundAd: NativeAd? = null }
    // A mock creative has no remote Google Play services binder. Capture only
    // that SDK boundary; all Android views and asset registration remain real.
    private var headline: View? = null
    private var body: View? = null
    private var cta: View? = null
    private var media: MediaView? = null
    @Implementation fun setHeadlineView(value: View) { headline = value }
    @Implementation fun getHeadlineView(): View? = headline
    @Implementation fun setBodyView(value: View) { body = value }
    @Implementation fun getBodyView(): View? = body
    @Implementation fun setCallToActionView(value: View) { cta = value }
    @Implementation fun getCallToActionView(): View? = cta
    @Implementation fun setMediaView(value: MediaView) { media = value }
    @Implementation fun getMediaView(): MediaView? = media
    @Implementation fun setNativeAd(ad: NativeAd) { boundAd = ad }
}

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34], manifest = Config.NONE, shadows = [NativeAdBindingShadow::class])
class RaceFeedNativeAdFactoryTest {
    @Test fun `factory binds headline and optional assets within the native row`() {
        // This isolated platform-view test has no merged application manifest.
        GooglePlayServicesUtilLight.enableUsingApkIndependentContext()
        val ad = mock(NativeAd::class.java)
        `when`(ad.headline).thenReturn("Race day")
        val view = RaceFeedNativeAdFactory(RuntimeEnvironment.getApplication()).createNativeAd(ad, null)
        assertEquals("Race day", (view.headlineView as TextView).text.toString())
        assertEquals(View.GONE, view.bodyView?.visibility)
        assertEquals(View.GONE, view.callToActionView?.visibility)
        assertNotNull(view.mediaView)
        assertSame(ad, NativeAdBindingShadow.boundAd)
    }
}
