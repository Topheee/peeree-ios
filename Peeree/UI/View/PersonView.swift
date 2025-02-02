//
//  PersonView.swift
//  Peeree
//
//  Created by Christopher Kobusch on 07.02.24.
//  Copyright © 2024 Kobusch. All rights reserved.
//

import SwiftUI

import PeereeCore

/*fileprivate*/ enum PinMatchAnimationPhase {
	case start, chargingUp, slamming

	static let chargeUpScale: CGFloat = 1.6

	static let pinPhaseAnimationDuration: CGFloat = 0.3
}

struct PersonView: View {
	init(peerID: PeerID, socialViewState: SocialViewState, discoveryViewState: DiscoveryViewState) {
		self.peerID = peerID
		self.discoveryPersona = discoveryViewState.persona(of: peerID)
		self.socialPersona = socialViewState.persona(of: peerID)
	}

	init(socialPersona: SocialPerson, discoveryPersona: DiscoveryPerson) {
		self.peerID = socialPersona.peerID
		self.socialPersona = socialPersona
		self.discoveryPersona = discoveryPersona
	}

	let peerID: PeerID

	@ObservedObject private var discoveryPersona: DiscoveryPerson

	@ObservedObject private var socialPersona: SocialPerson

	@EnvironmentObject private var socialViewState: SocialViewState

	@Environment(\.horizontalSizeClass) private var horizontalSizeClass
	@Environment(\.verticalSizeClass) private var verticalSizeClass

	@State private var compact = false

	@State private var showFlagAlert = false

	@State private var labelHeight = CGFloat.zero

	@State private var bioHeight = CGFloat.zero

	var body: some View {
		ZStack {
			LinearGradient(colors: [Color.accentColor, Color("ColorBackground")], startPoint: UnitPoint(x: 1, y: 1), endPoint: UnitPoint(x: 1, y: socialPersona.pinState == .pinMatch ? 0 : 1))
				.animation(.easeIn.delay(PinMatchAnimationPhase.pinPhaseAnimationDuration * 2).speed(1.8), value: socialPersona.pinState == .pinMatch)
				.ignoresSafeArea()

			AdaptiveStackView(orientation: verticalSizeClass == .compact ? .horizontal : .vertical) {
				AdaptiveStackView(orientation: compact ? .horizontal : .vertical) {
					discoveryPersona.image
						.resizable()
						.aspectRatio(contentMode: .fit)
						.blur(radius: socialViewState.classify(imageHash: discoveryPersona.pictureHash) != .none ? 10 : 0)
						.clipShape(Circle())
						.modify {
							if discoveryPersona.pictureProgress > 0.0 && discoveryPersona.pictureProgress < 1.0 {
								$0.overlay(CircularProgressView(progress: $discoveryPersona.pictureProgress))
							} else {
								$0
							}
						}
						.padding(.bottom, 4)
						.onTapGesture {
							withAnimation(.snappy) {
								compact.toggle()
							}
						}

					AdaptiveStackView(orientation: compact ? .horizontal : .vertical) {

						AdaptiveStackView(orientation: compact ? .vertical : .horizontal, horizontalAlignment: .leading) {
							if let age = discoveryPersona.info.age {
								TagView(text: "\(age)")
							}
							TagView(text: discoveryPersona.genderText)
						}

						PinButton(pinState: socialPersona.pinState, font: .title) {
							guard !discoveryPersona.isUser else { return }
							socialViewState.delegate?.pinToggle(peerID: peerID)
						}
						.padding([.bottom, .top])
						.modify {
							if #available(iOS 17, *) {
								$0.phaseAnimator([PinMatchAnimationPhase.start, PinMatchAnimationPhase.chargingUp, PinMatchAnimationPhase.slamming], trigger: socialPersona.pinState == .pinMatch) { content, phase in
									content.scaleEffect(CGSize(
										width:  phase == .start ? 1.0 : 
											(phase == .chargingUp ? PinMatchAnimationPhase.chargeUpScale :
												(phase == .slamming ? 0.01 : 1.0)),
										height: phase == .start ? 1.0 :
											(phase == .chargingUp ? PinMatchAnimationPhase.chargeUpScale :
												(phase == .slamming ? 0.01 : 1.0))
									))
								} animation: { phase in
									if phase == .chargingUp {
										.bouncy(duration:    PinMatchAnimationPhase.pinPhaseAnimationDuration,
												extraBounce: phase == .chargingUp ? 0.3 : 0.0)
									} else {
										.bouncy(duration:    PinMatchAnimationPhase.pinPhaseAnimationDuration / 2,
												extraBounce: phase == .chargingUp ? 0.3 : 0.0)
									}
								}
							}
						}
					}
				}

				VStack {
					VStack(alignment: .leading) {
						HStack {
							Circle()
								.fill(Color.gray)
								.frame(maxHeight: max(12, labelHeight - 8))
							Text("Biography")
								.font(.title2)
								.overlay(
									GeometryReader(content: { geometry in
										Color.clear
											.onAppear(perform: {
												self.labelHeight = geometry.frame(in: .local).size.height
											})
									})
								)

							Spacer()

							Capsule()
								.fill(Color.gray)
								.padding(.leading, 12)
								.frame(maxWidth: 64, maxHeight: max(12, labelHeight - 8))
						}

						ScrollView(.vertical) {
							HStack {
								Text(discoveryPersona.biography == "" ? NSLocalizedString("No biography.", comment: "SwiftUI") : (compact ? NSLocalizedString("Tap to show biography.", comment: "SwiftUI") : discoveryPersona.biography))
									.font(.body)
									.modify {
										if #available(iOS 16, *) {
											$0.italic(discoveryPersona.biography == "")
										} else {
											if discoveryPersona.biography == "" {
												$0.italic()
											} else {
												$0
											}
										}
									}
									.overlay(
										GeometryReader(content: { geometry in
											Color.clear
												.onAppear(perform: {
													self.bioHeight = geometry.frame(in: .local).size.height
												})
										})
									)

								if verticalSizeClass != .compact {
									Spacer()
								}
							}
						}
						.frame(maxHeight: compact ? min(bioHeight, 42) : bioHeight)

						if !compact && discoveryPersona.biography != "" {
							Text(discoveryPersona.info.nickname)
								.font(.custom("Bradley Hand", fixedSize: 24))
								.lineLimit(1)
								.foregroundColor(Color.indigo)
								.padding(.top, 8)
						}
					}
					.padding()
					.background(RoundedRectangle(cornerRadius: 16).fill(Color("ColorDivider")))
					.onTapGesture {
						withAnimation(.snappy) {
							compact.toggle()
						}
					}

					Text(discoveryPersona.peerID.uuidString)
						.font(.caption)
						.fontWeight(.light)
				}
			}
			.padding()
			.navigationTitle(discoveryPersona.info.nickname)
			.toolbar {
				ToolbarItem {
					Button {
						showFlagAlert.toggle()
					} label: {
						Image(systemName: "flag.fill")
							.resizable()
							.aspectRatio(contentMode: .fit)
							.frame(maxHeight: 34)
							.foregroundColor(.orange)
					}
					.disabled(discoveryPersona.isUser)
					.modify {
						if #available(iOS 15, *) {
							$0.alert(
								"Unpin or Report",
								isPresented: $showFlagAlert,
								presenting: discoveryPersona
							) { details in
								Button("Unpin", role: .destructive) {
									socialViewState.delegate?.removePin(peerID: peerID)
								}
								.disabled(!socialPersona.pinState.isPinned)
								Button("Report Portrait") {
									socialViewState.delegate?.reportPortrait(peerID: peerID)
								}
								.disabled(discoveryPersona.cgPicture == nil || socialViewState.classify(imageHash: discoveryPersona.pictureHash) != .none)
								Button("Cancel", role: .cancel) {

								}
							} message: { details in
								Text("Remove the pin or report the portrait of \(details.info.nickname).")
							}
						} else if socialPersona.pinState.isPinned || (discoveryPersona.cgPicture != nil && socialViewState.classify(imageHash: discoveryPersona.pictureHash) == .none) {
							$0.actionSheet(isPresented: $showFlagAlert) {
								ActionSheet(title: Text("Unpin or Report"),
											message: Text("Remove the pin or report the portrait of \(discoveryPersona.info.nickname)."),
											buttons: [
												.cancel(),
												.destructive(
													Text("Unpin")) {
														socialViewState.delegate?.removePin(peerID: peerID)
													},
												.default(
													Text("Report Portrait")) {
														socialViewState.delegate?.reportPortrait(peerID: peerID)
													}])
							}
						}
					}
				}
			}
		}
		.onAppear {
			if socialPersona.pinState == .pinMatch {
				UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
			}
		}
	}
}

#Preview {
	let ds = DiscoveryViewState()
	let ss = SocialViewState()
	let p = ds.demo()
	p.biography = "Lorem ipsum dolor colores senetra hila."
	return PersonView(peerID: p.peerID, socialViewState: ss, discoveryViewState: ds)
		.environmentObject(ss)
}

#Preview {
	let ds = DiscoveryViewState()
	let ss = SocialViewState()
	let p = ds.demo()
	p.biography = "Lorem ipsum dolor colores senetra hila. Lorem ipsum dolor colores senetra hila. Lorem ipsum dolor colores senetra hila. Lorem ipsum dolor colores senetra hila. Lorem ipsum dolor colores senetra hila. Lorem ipsum dolor colores senetra hila. Lorem ipsum dolor colores senetra hila. Lorem ipsum dolor colores senetra hila. Lorem ipsum dolor colores senetra hila. Lorem ipsum dolor colores senetra hila. Lorem ipsum dolor colores senetra hila. Lorem ipsum dolor colores senetra hila. Lorem ipsum dolor colores senetra hila. Lorem ipsum dolor colores senetra hila. "
	return PersonView(peerID: p.peerID, socialViewState: ss, discoveryViewState: ds)
		.environmentObject(ss)
}


#Preview("App Store Scene 2") {
	let language = "en"
	let path = Bundle.main.path(forResource: language, ofType: "lproj")
	let bundle = Bundle(path: path!)!

	let ds = DiscoveryViewState()
	let ss = SocialViewState()
	let p = ds.demo()
	p.info.age = 22
	p.info.gender = .female
	p.info.nickname = "Sarah"
	p.set(portrait: UIImage(named: "p1")?.cgImage, hash: Data())
	let bioFormat = bundle.localizedString(forKey: "Photo from Unsplash by %@.", value: nil, table: nil)
	p.biography = String(format: bioFormat, "Andrei Caliman")

	let sp = ss.demo(p.peerID)
	sp.pinState = .pinMatch

	return PersonView(peerID: p.peerID, socialViewState: ss, discoveryViewState: ds)
		.environmentObject(ss)
		.environment(\.locale, .init(identifier: language))
}
