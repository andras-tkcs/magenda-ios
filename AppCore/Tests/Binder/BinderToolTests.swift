// AppCore's binder tools: the pens' colors and names.

import AppCore
import Testing

@Suite("Binder tools")
struct BinderToolTests {
    @Test("The pens are black, blue, red and green, in that order")
    func order() {
        #expect(BinderPen.allCases == [.black, .blue, .red, .green])
    }

    @Test(
        "Each pen has its color and name",
        arguments: [
            (BinderPen.black, RGBColor(red: 0, green: 0, blue: 0), "Black"),
            (BinderPen.blue, RGBColor(red: 31, green: 95, blue: 209), "Blue"),
            (BinderPen.red, RGBColor(red: 209, green: 47, blue: 47), "Red"),
            (BinderPen.green, RGBColor(red: 30, green: 140, blue: 69), "Green"),
        ])
    func colorAndName(pen: BinderPen, color: RGBColor, name: String) {
        #expect(pen.color == color)
        #expect(pen.name == name)
        #expect(BinderPen(rawValue: name.lowercased()) == pen)
    }

    @Test("Tools compare by kind and pen")
    func equality() {
        #expect(BinderTool.pen(.red) == .pen(.red))
        #expect(BinderTool.pen(.red) != .pen(.blue))
        #expect(BinderTool.pen(.black) != .eraser)
    }
}
