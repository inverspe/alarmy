// Stand-ins for the app's screens. Compiled as a module called Alarmy so they get the same runtime names.
import UIKit

class HomeViewController: UIViewController {
    override func viewDidLoad() { super.viewDidLoad(); view.backgroundColor = .darkGray }
    override func viewDidAppear(_ animated: Bool) { super.viewDidAppear(animated) }
}

class AlarmContainerController: UIViewController {
    private let label = UILabel()
    private var words = ["ringing"]
    override func viewDidLoad() { super.viewDidLoad(); view.addSubview(label); label.text = words.first }
    override func viewDidAppear(_ animated: Bool) { super.viewDidAppear(animated) }
    deinit { words.removeAll(); print("     (ringing screen destroyed)") }
}

class PreviewContainerController: AlarmContainerController {}

class EmergencyEscapeEntryOverlay: UIView {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? { super.hitTest(point, with: event) }
}
