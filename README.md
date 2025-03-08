# neoclip

# SwiftUI Development Rules for macOS

You are an expert in SwiftUI, and your goal is to develop a macOS application while following best development practices. Follow these rules to ensure clean, maintainable, and scalable code.

## 1. Architecture and Code Organization

- **Use MVVM (Model-View-ViewModel)** to separate business logic from the UI.
- **Divide code into coherent modules**: do not mix data management and UI rendering.
- **Keep ViewModels lightweight** and responsible for a single functionality.
- **Prefer structs over classes**, unless an instance needs to be mutable and shared.
- **Do not use UIKit**, as SwiftUI is fully capable of handling macOS UI.

## 2. SwiftUI Components

- **Create reusable components**: each view should be small and specialized.
- **Use ViewModifiers** to encapsulate common styles and behaviors.
- **Prefer multiple small views** instead of one large, complex view.
- **Use `@ViewBuilder`** to structure reusable components.

## 3. State and Data Management

- **Use `@State` for local states**, `@StateObject` for ViewModels, and `@Binding` for inter-view communication.
- **Leverage `ObservableObject` and `@Published`** to manage dynamic data.
- **Use `EnvironmentObject` only for global dependencies**, and avoid overusing it.
- **Use Combine to handle events and updates**, instead of manual data passing.

## 4. Navigation and User Experience

- **Use `NavigationStack` instead of `NavigationView`** for modern applications.
- **Adopt a responsive design** that adapts to different macOS window sizes.
- **Use `ToolbarItem` instead of floating buttons** to follow macOS UX guidelines.
- **Enhance the user experience with subtle animations using `withAnimation{}`**.

## 5. Data Persistence and Management

- **Use `CoreData` or `FileManager`** for data storage if needed.
- **Perform database operations in the background** to keep the UI responsive.
- **Prefer `Codable` for data serialization/deserialization**.

## 6. Performance and Optimization

- **Avoid unnecessary UI updates** by optimizing `@Published` dependencies.
- **Use `LazyVStack` and `LazyHStack`** for large lists to improve performance.
- **Limit the use of `onAppear` and `task`** to avoid redundant API calls.
- **Minimize the use of `GeometryReader`**, as it can negatively impact performance.

## 7. Accessibility and Localization

- **Use `.accessibilityLabel()` and `.accessibilityHint()`** to make the app accessible.
- **Support `Dynamic Type`** to adapt to user-defined text sizes.
- **Use `LocalizedStringKey` (`Text("key")`)** to ensure app translation compatibility.

## 8. Testing and Debugging

- **Write unit tests for ViewModels** using `XCTest`.
- **Use `PreviewProvider` to quickly test views** with different data sets.
- **Monitor performance using `Instruments`** to detect memory leaks.
- **Prefer `os.log` over `print()`** for structured debugging logs.

## 9. Security and Best Practices

- **Do not expose sensitive data in plain text** in the code.
- **Use `Keychain` for storing sensitive information** like authentication tokens.
- **Enable `App Sandbox`** to limit access to system files and resources.

## 10. Code Conventions

- **Maintain a consistent coding style**, following SwiftLint guidelines.
- **Use explicit and meaningful variable and function names** for better readability.
- **Avoid unnecessary comments**, but document complex logic using `///`.
- **Use extensions to organize class and struct functionalities**.

---
