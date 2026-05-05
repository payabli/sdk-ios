# PayabliMauiDemo

Minimal .NET MAUI demo calling `PayabliPayIn` via the Xamarin.iOS binding
library skeleton in `Bridges/MAUI/PayabliBinding.cs`.

## Setup

1. Generate the binding project from the XCFramework using Objective Sharpie:
   ```bash
   dotnet tool install -g SharpieTool
   sharpie bind ../../build/PayabliSDK.xcframework --output ../../Bridges/MAUI
   ```
   Add resulting `ApiDefinitions.cs` + `StructsAndEnums.cs` to `PayabliBinding.csproj`.
2. Restore + build:
   ```bash
   dotnet restore
   dotnet build -f net8.0-ios17.0
   ```
3. Wire `FetchAccessTokenFromPartnerBackend()` in `MainPage.xaml.cs` to your
   backend's token endpoint.

## Not included in the scaffold

The full MAUI project (`Platforms/iOS/AppDelegate.cs`, `MauiProgram.cs`, etc.)
— generate with `dotnet new maui` then drop in this `MainPage.xaml.cs`.
