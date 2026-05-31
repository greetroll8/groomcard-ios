import SwiftUI

// Intentionally empty.
//
// The Owners tab is provided by `OwnersView` in `App/MainTabView.swift`, which
// owns the canonical owner list / detail / edit flow. The standalone
// `OwnersListView` / `OwnerDetailView(ownerId:)` / `OwnerEditView` defined here
// previously collided with that flow (duplicate type definitions) and referenced
// a non-existent `PetDetailView(petId:)` initializer, so they were removed.
