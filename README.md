# Peeree iOS

This project contains the source code of the [Peeree](https://www.peeree.de/) iOS app available on the [App Store](https://itunes.apple.com/us/app/peeree/id1363719515?l=en&ls=1&mt=8). If you are a developer and like to get the latest stuff, feel free to join the [Beta](https://testflight.apple.com/join/nEontnke).

## Building the App

For the *Peeree* target in the Xcode project's settings, change the developer profile to your own profile and change the `Bundle Identifier` as well.
Simply open `Peeree.xcodeproj` using Xcode and hit `build`.

## Debugging
Create an `LLDBInitFile` at the root of this project and add the path to the cloned `matrix-ios-sdk` repository to the source map:
```
settings set target.source-map /Users/runner/work/MatrixSDK/MatrixSDK/matrix-ios-sdk/MatrixSDK /path/to/matrix-ios-sdk/MatrixSDK
```

## External Dependencies

- **Peeree Server**: The Peeree server acts as a proprietary trusted third party. Peeree uses its services via a RESTful API. 

## License

This Source Code Form is subject to the terms of the Mozilla Public
License, v. 2.0. If a copy of the MPL was not distributed with this
file, You can obtain one at http://mozilla.org/MPL/2.0/.

Copyright © 2021 Christopher Kobusch. All rights reserved.
