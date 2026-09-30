# Qwixit architecture

Qwixit uses feature-first MVVM inside a lightweight Clean Architecture shell. The goal is clear ownership and dependency direction without adding framework ceremony to a small macOS app.

## Layers

- `App/` is the composition root. It creates concrete dependencies, wires feature view models, and owns app lifecycle integration.
- `Core/` contains reusable presentation primitives with no feature-specific behavior.
- `Infrastructure/` contains app-wide adapters for macOS, persistence, networking, and hotkeys.
- `Features/<Feature>/Domain/` contains feature language, models, and dependency contracts.
- `Features/<Feature>/Data/` contains concrete data access and external API implementations.
- `Features/<Feature>/Services/` contains focused platform or orchestration helpers local to one feature.
- `Features/<Feature>/Presentation/` contains SwiftUI views, observable view models, and AppKit window or panel coordinators.

Not every feature needs every folder. Create a layer only when the feature has code that belongs there.

## Dependency direction

`Presentation -> Domain <- Data/Infrastructure`

- Views render state and send user intent to a view model.
- View models own presentation state and async task lifetime. They depend on protocols when an effect crosses a process or platform boundary.
- Data and infrastructure types implement those protocols.
- `App` is the only place that should normally choose concrete implementations.
- Features must not reach into another feature's presentation layer. Shared behavior moves to `Core` or an app-wide infrastructure contract.

## Naming and ownership

- Observable presentation models end in `ViewModel`, not `Store`.
- AppKit objects that own windows or panels end in `WindowController` or `PanelController`.
- Global settings live in `SettingsViewModel`; one-shot text replacement lives in `QuickImproveViewModel`.
- A view model must expose read-only state where mutation is not a user-editable binding.
- Long-running `Task` instances are retained and cancelled when their owner stops.

## Testing

- View-model tests use protocol fakes and assert state transitions and requested effects.
- Domain logic is tested without SwiftUI or AppKit.
- Infrastructure tests cover serialization and boundary behavior.
- App composition gets a build smoke test so missing wiring is caught by CI.

## Review checklist

Before adding code, verify that the file is under the owning feature, its folder matches its responsibility, dependencies point inward, side effects are injectable where testing matters, and no new app-wide state has been added to a catch-all object.
