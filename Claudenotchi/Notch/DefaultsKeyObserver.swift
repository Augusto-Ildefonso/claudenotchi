import Foundation

/// Calls `onChange` when any of the given user-default keys changes, including changes made by another process
/// (`defaults write`, a settings sync). `UserDefaults.didChangeNotification` does not report those.
final class DefaultsKeyObserver: NSObject {
    private let keys: [String]
    private let onChange: () -> Void

    init(keys: [String], onChange: @escaping () -> Void) {
        self.keys = keys
        self.onChange = onChange
        super.init()
        for key in keys {
            UserDefaults.standard.addObserver(self, forKeyPath: key, options: [.new], context: nil)
        }
    }

    deinit {
        for key in keys {
            UserDefaults.standard.removeObserver(self, forKeyPath: key)
        }
    }

    override func observeValue(
        forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey: Any]?, context: UnsafeMutableRawPointer?
    ) {
        DispatchQueue.main.async { [onChange] in onChange() }
    }
}
