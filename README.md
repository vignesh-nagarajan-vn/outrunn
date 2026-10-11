# outrunn

Outrun your age: an iOS app that estimates biological, cardiac, and pulmonary age from a phone camera scan plus Apple Health.

## What it does

- Reads pulse and breathing from a short camera scan (Presage SmartSpectra) and, if you allow it, sleep, steps, HRV, and heart rate from Apple Health.
- Turns those into three ages with a fixed on-device formula, and shows which inputs add or remove years. Missing inputs are left out, not guessed.
- Sends the numbers (never video) to Gemini to explain them and suggest a recovery plan. The model never changes the ages.

## Run the app

1. Open `outrunn.xcodeproj` in Xcode 26 or later. The app targets iOS 18.
2. Copy `Secrets.example.xcconfig` to `Secrets.xcconfig`, then set your Presage key and the URL of your deployed `web/` project.
3. Pick your team under Signing & Capabilities and run on a physical iPhone. The camera scan and Apple Health do not work in the simulator.
4. To run the tests, add a Unit Testing Bundle target named `outrunnTests` that points at the `outrunnTests/` folder, then press Cmd+U.

## Deploy the website

1. Run `npx vercel link` inside `web/`, then `npx vercel env add GEMINI_API_KEY production`.
2. Run `npx vercel --prod`. This serves the landing page and the two coach endpoints, `/api/plan` and `/api/roadrunner`.
3. Put the deployed URL in `Secrets.xcconfig` as `COACH_BASE_URL`.

## Stack

Swift, SwiftUI, HealthKit, Presage SmartSpectra 3.0.0, Vercel serverless functions (Node), Gemini.

## Credits

Builds on [outrunn](https://github.com/krishh-12/outrunn), created by Amulya Bisaria, Anish Koduri, Krish Hariharan, and Srivanth Rudrangi at HackRice 16, where it won the Gemini API Integration award, sponsored by Google. See the [Devpost page](https://devpost.com/software/tamu-8zs5vy).

## Disclaimer

outrunn is a wellness tool. It is not medical advice or a diagnosis.
