/// The client's own terms of use and community guidelines.
///
/// Distinct from a *server's* Terms of Service (`tos_gate.dart`), which is
/// per-instance, optional, and only readable once authenticated — see #289. An
/// account is always created on somebody else's Accord instance, so the app
/// needs terms of its own that can be shown before any server is reachable,
/// and App Store Review Guideline 1.2 requires them to be presented before a
/// user registers *or* signs in.
library;

/// Bumped whenever [appTermsBody] changes materially. Acceptance is recorded
/// against this number, so a bump re-prompts everyone.
const int appTermsVersion = 1;

const String appTermsTitle = 'Terms of Use & Community Guidelines';

/// One-line summary used next to the acceptance control.
const String appTermsSummary =
    'Daccord has a zero-tolerance policy for objectionable content and '
    'abusive behaviour.';

/// Where a user reports a problem with the app itself (as opposed to content
/// on a particular server, which goes to that server's moderators).
const String appTermsContactUrl =
    'https://github.com/DaccordProject/daccord/issues';

const String appTermsBody = '''
Last updated: 30 August 2026

1. Accepting these terms

By using Daccord you agree to these Terms of Use and Community Guidelines. If
you do not agree, do not use the app.

2. What Daccord is

Daccord is a client application. It connects to Accord servers (also called
instances) that are run by other people and organisations, not by us. Each
server sets its own rules, keeps its own data, and is moderated by its own
operators and moderators. When you register an account you are registering with
that server, and its rules apply to you in addition to these terms.

3. Your content

You keep ownership of what you post. You are responsible for it, and you confirm
you have the right to post it. Anything you send is transmitted to, and stored
by, the server you sent it to.

4. Zero tolerance for objectionable content and abusive behaviour

There is no tolerance for objectionable content or for users who behave
abusively. You must not use Daccord to post, send, or share:

  - sexual content involving minors, or any content that sexualises a minor;
  - harassment, bullying, stalking, or threats;
  - hate speech, or attacks on people based on race, ethnicity, national origin,
    religion, disability, sex, gender identity, sexual orientation, or age;
  - violent, graphic, or gratuitously shocking material;
  - content encouraging self-harm or suicide;
  - terrorist or violent extremist material;
  - spam, scams, fraud, or malware;
  - content that is illegal where you are, or where the server you post to is
    operated.

5. Reporting and blocking

Every message and every account can be reported from inside the app. Use the
message's Report action, or Report user on an account, to flag anything that
breaks these guidelines. Reports of content posted in a space go to that space's
moderators, who are expected to act on them promptly — typically within 24
hours — by removing content, or by kicking or banning the account responsible.

You can also block any account at any time. Blocking stops that account from
messaging you and hides its content from you. Blocking is yours alone: it takes
effect immediately and does not require anyone's approval.

Reporting content does not guarantee a particular outcome, and moderation
decisions on a server are made by that server's operators.

6. Consequences

Server operators may remove your content, or suspend or terminate your account
on their server, if you break these guidelines or their own rules. Accounts used
to post objectionable content or to abuse other users may be removed without
notice.

7. Privacy

Daccord does not collect analytics, does not show ads, and does not track you.
What you send goes to the server you chose and nowhere else. Read that server's
own privacy policy to understand how it handles your data.

8. The software

Daccord is free and open-source software, licensed under the GNU General Public
License version 3. It is provided "as is", without warranty of any kind, to the
extent permitted by law. Nothing in these terms limits the rights the GPL grants
you in the software itself.

9. Changes

These terms may be updated. A material change re-prompts you to accept the new
version before you continue.

10. Contact

Problems with the app, including anything in these terms, can be raised at
$appTermsContactUrl. Content posted on a particular
server is handled by that server's moderators through the in-app report action.
''';
