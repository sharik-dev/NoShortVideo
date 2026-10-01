//
//  HomeCatView.swift
//  No short video
//
//  Un chat en silhouette, d'une seule couleur (le rouge de l'app), qui vit sur
//  l'écran d'accueil : il se promène sur la bande du bas, grimpe s'asseoir sur
//  les tuiles, s'endort. Plus on a regardé de vidéos aujourd'hui par rapport à
//  la limite quotidienne, plus il est somnolent — une jauge qui ne dit rien.
//
//  Les images viennent d'un vrai chat 3D animé (« Somali Cat Animated »,
//  DreamNoms, CC BY — crédité dans les réglages), rendu de profil en
//  silhouette blanche par Blender : six planches dans Assets.xcassets/Cat,
//  teintées ici en « template ». Le saut n'existe pas dans le modèle : il a
//  été posé à la main sur son squelette (IK sur les pattes). Queue affinée
//  au rendu. Scripts et marche à suivre : bibliothèque d'assets, SOURCE.md
//  du modèle.
//
//  Un tap sur lui : un cœur. Un tap sur la bande du bas : il y vient.
//  Expérimental : rien d'autre dans l'app n'en dépend, et il se coupe dans
//  les réglages (`enabledKey`).
//

import SwiftUI
import Combine

struct HomeCatView: View {

    /// Espace de coordonnées commun au chat et aux tuiles où il peut monter.
    static let space = "homeCat"
    static let enabledKey = "homeCatEnabled"
    /// Hauteur de la bande du bas que l'écran lui réserve.
    static let groundHeight: CGFloat = 76

    var color: Color
    /// Cadres des tuiles (dans `space`) : il s'assoit sur leur bord haut.
    var perches: [CGRect]
    /// Temps regardé aujourd'hui / limite quotidienne. 0 = en forme, ≥ 1 = il dort.
    var drowsiness: Double

    @StateObject private var cat = CatBrain()

    private let W = CatFrames.cellWidth
    private let H = CatFrames.cellHeight

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                // Bande du sol : le chat marche jusqu'au doigt. Le reste de
                // l'écran laisse passer les taps vers les tuiles.
                Color.clear
                    .frame(width: geo.size.width, height: Self.groundHeight)
                    .contentShape(Rectangle())
                    .onTapGesture { loc in cat.walk(to: loc.x) }
                    .position(x: geo.size.width / 2,
                              y: geo.size.height - 8 - Self.groundHeight / 2)

                // La cellule est plus large que le chat (place pour la queue) ;
                // `x` est le milieu de son corps, pas celui de l'image.
                let anchor = cat.facingRight ? CatFrames.anchor : 1 - CatFrames.anchor
                CatFrames.image(cat.clip, cat.frame)
                    .resizable()
                    .foregroundStyle(color)
                    .frame(width: W, height: H)
                    .scaleEffect(x: cat.facingRight ? 1 : -1, y: 1)
                    .position(x: cat.x - anchor * W + W / 2,
                              y: cat.y + CatFrames.groundInset - H / 2)
                    .allowsHitTesting(false)

                // Zone de tap resserrée sur le corps, pas sur toute la cellule.
                Color.clear
                    .frame(width: W * 0.5, height: H * 0.8)
                    .contentShape(Rectangle())
                    .onTapGesture { cat.poke() }
                    .position(x: cat.x, y: cat.y - H * 0.4)
                    .accessibilityLabel(Text("Cat"))

                bubble
                    .allowsHitTesting(false)
            }
            .onAppear {
                configure(geo.size)
                cat.start()
            }
            .onChange(of: geo.size) { _, s in configure(s) }
            .onChange(of: perches) { _, p in cat.perches = p }
            .onChange(of: drowsiness) { _, d in cat.drowsiness = d }
            .onDisappear { cat.stop() }
        }
    }

    private func configure(_ size: CGSize) {
        cat.halfBody = W * 0.3
        cat.minX = 20 + W * 0.3
        cat.maxX = max(cat.minX, size.width - 20 - W * 0.3)
        cat.groundY = size.height - 8
        cat.perches = perches
        cat.drowsiness = drowsiness
        cat.boundsChanged()
    }

    /// « z » quand il dort, un cœur quand on vient de le toucher. Posé
    /// au-dessus de sa tête, du côté où il regarde.
    @ViewBuilder private var bubble: some View {
        let seated = cat.isSeated
        let dx = (seated ? 0.14 : 0.25) * W
        let headX = cat.x + (cat.facingRight ? dx : -dx)
        let headY = cat.y - (seated ? 0.62 : 0.72) * H
        if cat.isSleeping {
            let phase = Int(cat.clock * 3) % 6
            Text("z")
                .font(.system(size: 13, weight: .heavy, design: .rounded))
                .foregroundStyle(color.opacity(0.7))
                .position(x: headX + CGFloat(phase) * (cat.facingRight ? 1.5 : -1.5),
                          y: headY - 6 - CGFloat(phase) * 3)
                .opacity(phase == 5 ? 0 : 1)
        } else if cat.showHeart {
            Image(systemName: "heart.fill")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(color)
                .position(x: headX, y: headY - 14)
                .transition(.scale.combined(with: .opacity))
        }
    }
}

// MARK: - Tuiles perchoirs

struct CatPerchKey: PreferenceKey {
    static var defaultValue: [CGRect] = []
    static func reduce(value: inout [CGRect], nextValue: () -> [CGRect]) {
        value.append(contentsOf: nextValue())
    }
}

extension View {
    /// Déclare cette vue comme un endroit où le chat de l'accueil peut s'asseoir.
    func catPerch() -> some View {
        background(GeometryReader { g in
            Color.clear.preference(key: CatPerchKey.self,
                                   value: [g.frame(in: .named(HomeCatView.space))])
        })
    }
}

// MARK: - Images

/// Les clips du chat, une planche par clip (8 colonnes). Marche et saut sont
/// rendus à 48 i/s pour la fluidité, le reste à 24.
enum CatClip: String {
    case idle = "CatIdle"
    case walk = "CatWalk"
    case sitDown = "CatSitDown"
    case sitting = "CatSitting"
    case standUp = "CatStandUp"
    case jump = "CatJump"

    var frameCount: Int {
        switch self {
        case .idle, .sitting: 48
        case .walk: 64
        case .sitDown, .standUp: 37
        case .jump: 61
        }
    }

    var fps: Double { self == .walk || self == .jump ? 48 : 24 }

    /// Les boucles ne contiennent pas d'image en double à la jonction.
    var loops: Bool { self == .idle || self == .walk || self == .sitting }

    /// Image d'une boucle à l'instant `t` (en secondes).
    func loopFrame(at t: Double) -> Int { Int(t * fps) % frameCount }
}

/// Aussi utilisé par l'écran « Prêt » de l'onboarding.
@MainActor
enum CatFrames {
    static let columns = 8
    static let cellPixels = CGSize(width: 260, height: 180)

    /// Taille d'affichage d'une cellule. La cellule couvre 7,8 unités du
    /// modèle en largeur : 120 pt → ~15,4 pt par unité.
    static let cellWidth: CGFloat = 120
    static let cellHeight: CGFloat = cellWidth * cellPixels.height / cellPixels.width
    /// Le sol du rendu est à 9,5 px (sur 270) du bas de la cellule.
    static let groundInset: CGFloat = cellHeight * 9.5 / 270
    /// Milieu du corps, en fraction de la largeur de cellule (chat tourné à droite).
    static let anchor: CGFloat = 0.65
    /// Une patte posée recule de 1,84 unité par cycle de marche (64 images) :
    /// c'est la distance à parcourir par image pour qu'elle ne glisse pas.
    static let walkStride: CGFloat = 1.84 / 64 * cellWidth / 7.8

    /// Découpage du saut (images à 48 i/s) : appel au sol, vol, réception.
    static let jumpTakeoff = 16
    static let jumpTouchdown = 40

    static func image(_ clip: CatClip, _ frame: Int) -> Image {
        // UIImage(named:) garde la planche en cache et la libère sous pression
        // mémoire ; le recadrage ne copie pas les pixels.
        guard let sheet = UIImage(named: clip.rawValue)?.cgImage else { return Image(systemName: "cat.fill") }
        let i = min(max(0, frame), clip.frameCount - 1)
        let rect = CGRect(x: CGFloat(i % columns) * cellPixels.width,
                          y: CGFloat(i / columns) * cellPixels.height,
                          width: cellPixels.width, height: cellPixels.height)
        guard let cell = sheet.cropping(to: rect) else { return Image(systemName: "cat.fill") }
        return Image(decorative: cell, scale: 1).renderingMode(.template)
    }
}

// MARK: - Comportement

@MainActor
private final class CatBrain: ObservableObject {

    enum Mode { case idle, walking, sittingDown, sitting, sleeping, standingUp, jumping }

    private struct Jump {
        enum Phase { case crouch, air, landing }
        let from: CGPoint
        let to: CGPoint
        /// Durée du vol, en secondes.
        let duration: Double
        /// Hauteur ajoutée au sommet de la parabole.
        let k: CGFloat
        let perch: Int?
        var phase = Phase.crouch
        var t = 0.0
    }

    @Published private(set) var mode: Mode = .sitting
    /// Milieu du corps, et ligne du sol sous ses pattes.
    @Published private(set) var x: CGFloat = 0
    @Published private(set) var y: CGFloat = 0
    @Published private(set) var facingRight = true
    /// Temps écoulé, en secondes (anime le « z »).
    @Published private(set) var clock = 0.0
    @Published private(set) var showHeart = false
    /// Position dans le clip courant, en images (fractionnaire).
    @Published private var playhead: Double = 0

    var minX: CGFloat = 0
    var maxX: CGFloat = 0
    var groundY: CGFloat = 0
    var halfBody: CGFloat = 36
    var perches: [CGRect] = []
    var drowsiness: Double = 0

    /// Tuile sur laquelle il est, nil = au sol.
    private var perch: Int?
    private var target: CGFloat = 0
    /// Secondes restantes avant de changer d'humeur.
    private var patience = 2.5
    private var heartLeft = 0.0
    private var jump: Jump?
    /// Ce qu'il fera une fois relevé.
    private var afterStandUp: (() -> Void)?
    private var started = false
    private var link: CADisplayLink?
    private var lastTimestamp: CFTimeInterval?

    private var sleepy: Double { min(1, max(0, drowsiness)) }

    var isSeated: Bool { mode == .sitting || mode == .sleeping || mode == .sittingDown }
    var isSleeping: Bool { mode == .sleeping }

    var clip: CatClip {
        switch mode {
        case .idle:                return .idle
        case .walking:             return .walk
        case .jumping:             return .jump
        case .sittingDown:         return .sitDown
        case .sitting, .sleeping:  return .sitting
        case .standingUp:          return .standUp
        }
    }

    var frame: Int {
        let n = clip.frameCount
        let f = Int(playhead)
        return clip.loops ? f % n : min(f, n - 1)
    }

    func start() {
        if !started {
            started = true
            x = minX + (maxX - minX) * 0.2
            y = groundY
            // Limite déjà atteinte : on le trouve endormi en ouvrant l'app.
            if sleepy >= 1 { setMode(.sleeping) } else { setMode(.sitting) }
            patience = 2.5
        }
        // Une image par rafraîchissement d'écran, plafonnée à 60 i/s : le
        // déplacement est lisse, et les planches (24/48 i/s) avancent au
        // temps réel écoulé.
        link?.invalidate()
        lastTimestamp = nil
        let l = CADisplayLink(target: DisplayLinkProxy { [weak self] link in self?.step(link) },
                              selector: #selector(DisplayLinkProxy.fire(_:)))
        l.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
        l.add(to: .main, forMode: .common)
        link = l
    }

    func stop() {
        link?.invalidate()
        link = nil
    }

    func boundsChanged() {
        guard started, perch == nil, mode != .jumping else { return }
        y = groundY
        x = clampX(x)
        target = clampX(target)
    }

    /// Tap sur la bande du bas.
    func walk(to position: CGFloat) {
        guard mode != .jumping else { return }
        let dest = clampX(position)
        whenStanding { [self] in
            if perch != nil {
                leap(to: CGPoint(x: dest, y: groundY), perch: nil)
            } else {
                target = dest
                if abs(dest - x) > 1 { facingRight = dest > x }
                setMode(.walking)
            }
        }
    }

    /// Tap sur le chat : un cœur. Endormi, il se réveille.
    func poke() {
        heartLeft = 1.7
        withAnimation(.spring(duration: 0.3)) { showHeart = true }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        if mode == .sleeping {
            setMode(.sitting)
            patience = 2
        }
    }

    // MARK: Boucle

    private func step(_ link: CADisplayLink) {
        let now = link.targetTimestamp
        // Pas de temps réel, borné : un retour d'arrière-plan ne le téléporte pas.
        let dt = min(1.0 / 20, max(0, now - (lastTimestamp ?? now)))
        lastTimestamp = now
        guard dt > 0 else { return }
        update(dt)
    }

    private func update(_ dt: Double) {
        clock += dt

        if heartLeft > 0 {
            heartLeft -= dt
            if heartLeft <= 0 { withAnimation(.easeOut(duration: 0.3)) { showHeart = false } }
        }

        // Sur une tuile : il la suit quand la grille défile, et tombe si
        // elle disparaît.
        if let p = perch, mode != .jumping {
            guard p < perches.count else {
                perch = nil
                afterStandUp = nil
                leap(to: CGPoint(x: x, y: groundY), perch: nil)
                return
            }
            x = perches[p].midX
            y = perches[p].minY
        }

        let frames = dt * clip.fps

        switch mode {
        case .walking:
            // La vitesse suit la foulée : les pattes restent collées au sol.
            let rate = 1.3 * (1 - 0.45 * sleepy)
            let advance = frames * rate
            let speed = CatFrames.walkStride * advance
            let d = target - x
            if abs(d) <= speed {
                x = target
                arrive()
            } else {
                x += d > 0 ? speed : -speed
                playhead += advance
            }

        case .jumping:
            updateJump(dt, frames: frames)

        case .sittingDown:
            playhead += frames
            if Int(playhead) >= clip.frameCount - 1 {
                setMode(.sitting)
                patience = .random(in: 3.5...10)
            }

        case .standingUp:
            playhead += frames
            if Int(playhead) >= clip.frameCount - 1 {
                setMode(.idle)
                patience = 0.8
                let next = afterStandUp
                afterStandUp = nil
                next?()
            }

        case .idle:
            playhead += frames
            patience -= dt
            if patience <= 0 { decideStanding() }

        case .sitting:
            playhead += frames
            patience -= dt
            if patience <= 0 { decideSeated() }

        case .sleeping:
            // Respiration ralentie.
            playhead += frames * 0.4
            patience -= dt
            if patience <= 0 {
                if Double.random(in: 0..<1) < sleepy * 0.8 {
                    patience = sleepDuration()
                } else {
                    setMode(.sitting)
                    patience = .random(in: 2.5...6.5)
                }
            }
        }
    }

    /// Saut en trois temps : il s'accroupit et prend son appel sur place,
    /// vole (les images de vol suivent la trajectoire), puis se réceptionne.
    private func updateJump(_ dt: Double, frames: Double) {
        guard var j = jump else { setMode(.idle); return }
        switch j.phase {
        case .crouch:
            playhead += frames
            if playhead >= Double(CatFrames.jumpTakeoff) {
                playhead = Double(CatFrames.jumpTakeoff)
                j.phase = .air
            }
        case .air:
            j.t = min(1, j.t + dt / j.duration)
            let t = CGFloat(j.t)
            x = j.from.x + (j.to.x - j.from.x) * t
            y = j.from.y + (j.to.y - j.from.y) * t - j.k * 4 * t * (1 - t)
            playhead = Double(CatFrames.jumpTakeoff)
                + j.t * Double(CatFrames.jumpTouchdown - CatFrames.jumpTakeoff)
            if j.t >= 1 {
                x = j.to.x
                y = j.to.y
                perch = j.perch
                j.phase = .landing
            }
        case .landing:
            playhead += frames
            if Int(playhead) >= clip.frameCount - 1 {
                jump = nil
                // Sur une tuile il s'installe ; au sol il reprend sa vie.
                if perch != nil { setMode(.sittingDown) } else { arrive() }
                return
            }
        }
        jump = j
    }

    // MARK: Décisions

    /// Debout : s'asseoir, flâner ou grimper sur une tuile.
    private func decideStanding() {
        let r = Double.random(in: 0..<1)
        let pSit = 0.3 + 0.5 * sleepy
        if r < pSit || perch != nil {
            setMode(.sittingDown)
            return
        }
        let reachable = perches.indices.filter { perches[$0].minY > 120 }
        if let p = reachable.randomElement(), r < pSit + 0.3 {
            leap(to: CGPoint(x: perches[p].midX, y: perches[p].minY), perch: p)
        } else {
            walk(to: .random(in: minX...maxX))
        }
    }

    /// Assis : s'endormir, ou se relever pour aller ailleurs.
    private func decideSeated() {
        if Double.random(in: 0..<1) < 0.25 + 0.6 * sleepy {
            setMode(.sleeping)
            patience = sleepDuration()
            return
        }
        if perch != nil {
            // Redescendre de la tuile.
            walk(to: .random(in: minX...maxX))
        } else {
            whenStanding { [self] in
                setMode(.idle)
                patience = .random(in: 0.8...2.5)
            }
        }
    }

    // MARK: Actions

    /// Assis ou endormi, il se relève avant de faire `action`.
    private func whenStanding(_ action: @escaping () -> Void) {
        switch mode {
        case .sitting, .sleeping, .sittingDown:
            afterStandUp = action
            setMode(.standingUp)
        case .standingUp:
            afterStandUp = action
        default:
            action()
        }
    }

    private func arrive() {
        setMode(.idle)
        patience = .random(in: 1.2...3.8)
    }

    private func leap(to dest: CGPoint, perch landing: Int?) {
        let from = CGPoint(x: x, y: y)
        let dist = hypot(dest.x - from.x, dest.y - from.y)
        if abs(dest.x - from.x) > 1 { facingRight = dest.x > from.x }
        perch = nil
        // Un saut plus long dure un peu plus, sans jamais traîner.
        jump = Jump(from: from, to: dest,
                    duration: min(0.85, 0.42 + Double(dist) / 900),
                    k: abs(from.y - dest.y) / 2 + 26,
                    perch: landing)
        setMode(.jumping)
    }

    private func setMode(_ m: Mode) {
        mode = m
        playhead = 0
    }

    private func sleepDuration() -> Double {
        .random(in: 6...15) * (1 + 2 * sleepy)
    }

    private func clampX(_ v: CGFloat) -> CGFloat { min(max(minX, v), maxX) }
}

/// CADisplayLink retient sa cible : ce relais évite de retenir le chat.
private final class DisplayLinkProxy: NSObject {
    let tick: (CADisplayLink) -> Void
    init(_ tick: @escaping (CADisplayLink) -> Void) { self.tick = tick }
    @objc func fire(_ link: CADisplayLink) { tick(link) }
}

#Preview {
    ZStack {
        HomeCatView(color: .red, perches: [CGRect(x: 60, y: 300, width: 76, height: 76)], drowsiness: 0.2)
    }
    .coordinateSpace(.named(HomeCatView.space))
}
