# SwiftyTimer

![Platforms](https://img.shields.io/badge/platforms-ios%20%7C%20osx%20%7C%20watchos%20%7C%20tvos-lightgrey.svg)
[![CI Status](https://api.travis-ci.org/radex/SwiftyTimer.svg?branch=master)](https://travis-ci.org/radex/SwiftyTimer)
[![CocoaPods](http://img.shields.io/cocoapods/v/SwiftyTimer.svg)](https://cocoapods.org/pods/SwiftyTimer)
[![Carthage compatible](https://img.shields.io/badge/Carthage-compatible-4BC51D.svg?style=flat)](#carthage)
![Swift version](https://img.shields.io/badge/swift-3.0-orange.svg)

#### Modern Swifty API for `NSTimer`
###### SwiftyTimer allows you to instantly schedule delays and repeating timers using convenient closure syntax. It's time to get rid of Objective-C cruft.

Read [Swifty APIs: NSTimer](http://radex.io/swift/nstimer/) for more information about this project.

## Usage

You can easily schedule repeating and non-repeating timers (repeats and delays) using `Timer.every` and `Timer.after`:

```swift
Timer.every(0.7.seconds) {
    statusItem.blink()
}

Timer.after(1.minute) {
    println("Are you still here?")
}
```

You can specify time intervals with these intuitive helpers:

```swift
100.ms
1.second
2.5.seconds
5.seconds
10.minutes
1.hour
2.days
```

You can pass method references instead of closures:

```swift
Timer.every(30.seconds, align)
```

### Manual scheduling

If you want to make a timer object without scheduling, use `new(after:)` and `new(every:)`:

```swift
let timer = Timer.new(every: 1.second) {
    println(self.status)
}
```

(This should be defined as an initializer, but [a bug in Foundation](http://www.openradar.me/18720947) prevents this)

Call `start()` to schedule timers created using `new`. You can optionally pass the run loop and run loop modes:

```swift
timer.start()
timer.start(modes: .defaultRunLoopMode, .eventTrackingRunLoopMode)
```

### Invalidation

If you want to invalidate a repeating timer on some condition, you can take a `Timer` argument in the closure you pass in:

```swift
Timer.every(5.seconds) { (timer: Timer) in
    // do something
    
    if finished {
        timer.invalidate()
    }
}
```

## Installation

**Note:** If you're running Swift 2, use [SwiftyTimer v1.4.1](https://github.com/radex/SwiftyTimer/tree/1.4.1)

#### CocoaPods

If you're using CocoaPods, just add this line to your Podfile:

```ruby
pod 'SwiftyTimer'
```

Install by running this command in your terminal:

```sh
pod install
```

Then import the library in all files where you use it:

```swift
import SwiftyTimer
```

#### Carthage

Just add to your Cartfile:

```ruby
github "radex/SwiftyTimer"
```

#### Manually

Simply copy `Sources/SwiftyTimer.swift` to your Xcode project.

## More like this

If you like SwiftyTimer, check out [SwiftyUserDefaults](https://github.com/radex/SwiftyUserDefaults), which applies the same swifty approach to `NSUserDefaults`.

You might also be interested in my blog posts which explain the design process behind those libraries:
- [Swifty APIs: NSTimer](http://radex.io/swift/nstimer/)
- [Swifty APIs: NSUserDefaults](http://radex.io/swift/nsuserdefaults/)
- [Statically-typed NSUserDefaults](http://radex.io/swift/nsuserdefaults/static)
- [Swifty methods](http://radex.io/swift/methods/)

### Contributing

If you have comments, complaints or ideas for improvements, feel free to open an issue or a pull request.

### Author and license

Radek Pietruszewski

* [github.com/radex](http://github.com/radex)
* [twitter.com/radexp](http://twitter.com/radexp)
* [radex.io](http://radex.io)
* this.is@radex.io

SwiftyTimer is available under the MIT license. See the LICENSE file for more info.
