import SwiftUI

// Intentionally empty.
//
// `OwnerDetailView` is provided by `App/MainTabView.swift` with the
// `OwnerDetailView(owner:)` initializer used by the Owners and Pets navigation
// stacks. The duplicate `OwnerDetailView(ownerId:)` that lived here caused a
// redeclaration error and also called a non-existent `PetDetailView(petId:)`
// initializer, so it was removed.
