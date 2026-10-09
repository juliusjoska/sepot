package cz.sepot.sepot

import android.content.pm.ApplicationInfo
import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterFragmentActivity

class MainActivity : FlutterFragmentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Soukromí: zákaz screenshotů a náhledu obsahu v přepínači aplikací.
        // Výchozí stav; Dart přepínač „Zabezpečení obrazovky" ho může po
        // odemčení vypnout (default zapnuto, jako u Signalu).
        // Debug build: screenshoty povolené kvůli QA na emulátoru (adb screencap
        // by u FLAG_SECURE okna selhal); release vždy chráněný.
        val debuggable = (applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE) != 0
        if (!debuggable) {
            window.setFlags(
                WindowManager.LayoutParams.FLAG_SECURE,
                WindowManager.LayoutParams.FLAG_SECURE,
            )
        }
        // Tapjacking: dotyky přes překryvné okno jiné appky (částečně
        // průhledný overlay nad PIN klávesnicí) se zahodí.
        window.decorView.filterTouchesWhenObscured = true
    }
}
