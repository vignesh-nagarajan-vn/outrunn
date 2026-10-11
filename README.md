<h1 align="center">outrunn</h1>

<p align="center"><i>outrun your age</i></p>

<p align="center">
  Builds on <a href="https://github.com/krishh-12/outrunn">outrunn</a>, created by Amulya Bisaria, Anish Koduri, Krish Hariharan, and Srivanth Rudrangi at HackRice 16, where it won the Gemini API Integration award, sponsored by Google. See the <a href="https://devpost.com/software/tamu-8zs5vy">Devpost page</a>.
</p>

- Live on Vercel: [outrunn.vercel.app](https://outrunn.vercel.app)

<!--- iOS app --->
<p align="center"><sub><b>iOS App:</b></sub></p>
<p align="center">
  <img src="https://img.shields.io/badge/swift-%23F54A2A.svg?style=for-the-badge&logo=swift&logoColor=white">
  <img src="https://img.shields.io/badge/SwiftUI-%230D96F6.svg?style=for-the-badge&logo=swift&logoColor=white">
  <img src="https://img.shields.io/badge/Swift%20Charts-%23F54A2A.svg?style=for-the-badge&logo=swift&logoColor=white">
  <img src="https://img.shields.io/badge/HealthKit-%23FF2D55.svg?style=for-the-badge&logo=apple&logoColor=white">
  <img src="https://img.shields.io/badge/iOS%2018-%23000000.svg?style=for-the-badge&logo=ios&logoColor=white">
  <img src="https://img.shields.io/badge/Xcode-%23147EFB.svg?style=for-the-badge&logo=xcode&logoColor=white">
  <img src="https://img.shields.io/badge/XCTest-%23147EFB.svg?style=for-the-badge&logo=xcode&logoColor=white">
</p>

<!--- AI and vitals --->
<p align="center"><sub><b>AI & Vitals:</b></sub></p>
<p align="center">
  <img src="https://img.shields.io/badge/Google%20Gemini-%238E75B2.svg?style=for-the-badge&logo=googlegemini&logoColor=white">
  <img src="https://img.shields.io/badge/Presage%20SmartSpectra-%2352ADB8.svg?style=for-the-badge">
</p>

<!--- Web and infrastructure --->
<p align="center"><sub><b>Web & Infrastructure:</b></sub></p>
<p align="center">
  <img src="https://img.shields.io/badge/vercel-%23000000.svg?style=for-the-badge&logo=vercel&logoColor=white">
  <img src="https://img.shields.io/badge/node.js-6DA55F?style=for-the-badge&logo=node.js&logoColor=white">
  <img src="https://img.shields.io/badge/javascript-%23323330.svg?style=for-the-badge&logo=javascript&logoColor=%23F7DF1E">
  <img src="https://img.shields.io/badge/html5-%23E34F26.svg?style=for-the-badge&logo=html5&logoColor=white">
  <img src="https://img.shields.io/badge/css3-%231572B6.svg?style=for-the-badge&logo=css3&logoColor=white">
</p>

## Functionality

- Reads pulse and breathing from a short camera scan (Presage SmartSpectra) and, if you allow it, sleep, steps, HRV, and heart rate from Apple Health.
- Turns those into three ages with a fixed on-device formula, and shows which inputs add or remove years. Missing inputs are left out, not guessed.
- Sends the numbers (never video) to Gemini to explain them and suggest a recovery plan. The model never changes the ages.

## *Runn* the App

```bash
git clone https://github.com/vignesh-nagarajan-vn/outrunn
cd outrunn
cp Secrets.example.xcconfig Secrets.xcconfig   # then set your Presage key and coach URL
open outrunn.xcodeproj                         # pick your team, run on a physical iPhone
```
