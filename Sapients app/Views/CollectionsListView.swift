import SwiftUI
import Supabase

struct CollectionTileView: View {
    let collection: Collection
    /// Optional namespace used for hero animation. Pass from parent when needed.
    var coverNamespace: Namespace.ID?
    
    @Environment(\.colorScheme) private var scheme
    
    var body: some View {
        ZStack(alignment: .leading) {
            // Adaptive background: white in light mode, black in dark mode
            let tileColor: Color = scheme == .light ? .white : .black
            RoundedRectangle(cornerRadius: Tokens.Corner.r2)
                .fill(tileColor)
                .cardShadow()
            HStack(alignment: .top, spacing: Tokens.Spacing.l) {
                coverImage
                    .frame(width: 132, height: 211)
                    .clipShape(RoundedRectangle(cornerRadius: Tokens.Corner.r2))
                VStack(alignment: .leading, spacing: 6) {
                    Text(collection.title)
                        .font(.custom("Didot-Bold", size: 24))
                        .foregroundColor(.primary)
                    if let desc = collection.description {
                        Text(desc)
                            .font(.footnote)
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    }
                }
                Spacer()
            }
            .padding(Tokens.Spacing.s)
        }
        .frame(maxWidth: .infinity, minHeight: 220)
    }

    // MARK: - cover image with optional matched-geometry effect + bottom fade
    @ViewBuilder private var coverImage: some View {
        // gradient overlay for bottom blur
        let gradientOverlay = LinearGradient(
            colors: [Color.black.opacity(0.3), .clear],
            startPoint: .bottom,
            endPoint: UnitPoint(x: 0.5, y: 0.2)
        )
        .clipShape(RoundedRectangle(cornerRadius: Tokens.Corner.r2))

        if let url = getCollectionImageURL(for: collection) {
            let remote = CachedAsyncImage(url: url) { placeholder }
            if let ns = coverNamespace {
                remote
                    .aspectRatio(contentMode: .fill)
                    .matchedGeometryEffect(id: "cover-\(collection.id)", in: ns)
                    .overlay(gradientOverlay)
            } else {
                remote
                    .aspectRatio(contentMode: .fill)
                    .overlay(gradientOverlay)
            }
        } else {
            if let ns = coverNamespace {
                placeholder
                    .aspectRatio(contentMode: .fill)
                    .matchedGeometryEffect(id: "cover-\(collection.id)", in: ns)
                    .overlay(gradientOverlay)
            } else {
                placeholder
                    .aspectRatio(contentMode: .fill)
                    .overlay(gradientOverlay)
            }
        }
    }

    private var placeholder: some View {
        Rectangle().fill(Color.gray.opacity(0.3))
    }
}

struct CollectionsListView: View {
    @StateObject private var repository = CollectionRepository()
    @Namespace private var coverNS
    @EnvironmentObject private var contentRepo: ContentRepository
    @EnvironmentObject private var audioPlayer: AudioPlayerService
    @EnvironmentObject private var miniState: MiniPlayerState
    @Environment(\.colorScheme) private var scheme
    
    @State private var resumeContent: Content? = nil
    @State private var resumePosition: Double = 0

    var body: some View {
        NavigationView {
            ZStack(alignment: .top) {
                // Layer 1: Scrollable content behind the header
                content
                    .ignoresSafeArea(edges: .top) // allow content to slide under header

                // Layer 2: Fixed header overlay
                header
            }
            .navigationBarHidden(true)
        }
        .onAppear {
            Task {
                await repository.fetchAllCollections()
                if let (episode, pos) = AudioPlayerService.loadSavedProgress() {
                    resumeContent = episode
                    resumePosition = pos
                }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if repository.isLoading {
            ProgressView("Loading collections…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if repository.collections.isEmpty {
            VStack {
                Image(systemName: "books.vertical")
                    .font(.system(size: 50))
                    .foregroundColor(.secondary.opacity(0.6))
                Text("No collections available")
                    .font(.headline)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 24) {
                    // Spacer to offset content below the floating header height (150)
                    Spacer().frame(height: 150)

                    if let resume = resumeContent {
                        Text("Jump back in")
                            .font(.title2.bold())
                            .padding(.horizontal, 16)
                        JumpBackInView(content: resume) {
                            // resume action
                            let url: URL?
                            if resume.audioUrl.starts(with: "http") {
                                url = URL(string: resume.audioUrl)
                            } else {
                                url = try? SupabaseManager.shared.client.storage.from("audio").getPublicURL(path: resume.audioUrl)
                            }
                            if let audioURL = url {
                                audioPlayer.loadAudio(from: audioURL, for: resume, autoPlay: true)
                                audioPlayer.seek(to: resumePosition)
                                miniState.presentFullPlayer()
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 8)
                    }

                    ForEach(repository.collections) { collection in
                        NavigationLink(destination: EpisodesListView(collection: collection, coverNamespace: coverNS)) {
                            CollectionTileView(collection: collection, coverNamespace: coverNS)
                        }
                        .buttonStyle(.plain)
                        .scrollTransition(axis: .vertical) { content, phase in
                            content
                                .opacity(phase.isIdentity ? 1 : 0)
                                .offset(y: phase.isIdentity ? 0 : 40)
                        }
                    }
                }
                // Keep horizontal padding but remove top padding (handled by spacer).
                .padding(.horizontal, Tokens.Spacing.l)
                // Fix: Add proper bottom padding for tab bar and mini player
                .padding(.bottom, 120)
            }
            .background(Color(.systemBackground))
            // Content now allowed to scroll under header
            // IMPORTANT: The ScrollView should ignore the top safe area
            .ignoresSafeArea(edges: .top)
        }
    }

    // MARK: Header
    private var header: some View {
        let isLight = scheme == .light
        let bg = isLight ? Color.black : Color.white
        let fg = isLight ? Color.white : Color.black
        // Header with title anchored at the bottom to mimic Episode header styling
        return ZStack {
            bg
            VStack {
                Spacer() // pushes content to the bottom edge
            HStack {
                Text("Collections")
                        .font(.largeTitle.bold())
                    .foregroundColor(fg)
                Spacer()
            }
            .padding(.horizontal, Tokens.Spacing.l)
            .padding(.bottom, Tokens.Spacing.s)
            }
        }
        .frame(height: 150)
        .ignoresSafeArea(edges: .top)
    }
}

// helper func reuse from earlier
private func getCollectionImageURL(for collection: Collection) -> URL? {
    guard var imgPath = collection.imageUrl else { return nil }
    // Remove accidental whitespace/newline characters that might break the URL.
    imgPath = imgPath.trimmingCharacters(in: .whitespacesAndNewlines)

    if imgPath.hasPrefix("collections/") {
        let clean = String(imgPath.dropFirst("collections/".count))
        return try? SupabaseManager.shared.client.storage.from("collections").getPublicURL(path: clean)
    } else {
        return try? SupabaseManager.shared.client.storage.from("images").getPublicURL(path: imgPath)
    }
}

struct CollectionsListView_Previews: PreviewProvider {
    static var previews: some View {
        CollectionsListView()
    }
} 
