# VSCode Theming Tools (in Dart)

Have you ever been annoyed at making more complex themes for VSCode by hand-writing your patterns and regular expressions in TextMate's JSON format? (No? Just me?) 

Well, if so, this library is just for you!

This library provides an easy way to dynamically construct regular expressions and configure the language patterns VSCode needs to recognize your favorite language. No more copy-pasting your JSON configurations and spending hours debugging "Which rule is breaking this and what the heck is wrong with it?"; With this library, your rules and regexes can have dependencies on each other, making changes to them easy to make, and (with the injected debugging scopes) tracking bugs even easier.


## How do I use it?

Since this library is written in dart, you'll have to make a small dart project and import this as a library:

- Make sure `dart` is installed ([download here](https://dart.dev/get-dart); check with `dart --version`)
- Make a new directory for your project and add a `pubspec.yaml` file (see [this guide](https://dart.dev/guides/packages) for additional info on dart libraries/packages)
- Run `dart pub add vscode_theming_tools` to add this library to your project
- Add `import 'vscode_theming_tools/vscode_theming_tools.dart` to the top of your dart file

And that's it! You can now use all the tooling this library offers.


## What does this library offer?

(I still need to write this section... Bug me if this is an issue for you.)

(I should also probably add some examples...)
