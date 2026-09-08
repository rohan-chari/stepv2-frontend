Timing note: the policy is now fixed—immediate first permanent rewards for free/trial accounts, otherwise the original paid period end, then UTC monthly anniversaries. The planner text below is preserved verbatim.

**Manual UI-Placement Test Plan — Monthly and permanent Bara+**

*Elements under test:*\
Replace the yearly purchase option with permanent premium beside monthly.\
Add permanent ownership and next-reward information to the membership screen.\
Retain subscription management and add cancellation guidance when permanent ownership overlaps a monthly subscription.\
Update existing Shop, Get Coins and Profile membership cards without moving navigation.

*Checklist*

1. **Real membership screen — available offers**
   - **Get there:** With a nonmember test account, open Shop → Bara+.
   - **Verify:** Monthly and permanent options appear together in the existing offer area. The yearly purchase option is absent. Monthly trial information stays with monthly; permanent purchase information stays with permanent. Purchase, restore and legal controls remain reachable below the benefits without duplicate buttons.

2. **Real membership screen — permanent owner**
   - **Get there:** With a permanent-owner test account, open Profile → Bara+.
   - **Verify:** Permanent ownership and the next-reward date appear in the membership area. No repeat permanent-purchase button or monthly signup remains. Restore and legal controls remain reachable. There is no empty expiry placeholder or leftover yearly selector.

3. **Real membership screen — permanent plus monthly**
   - **Get there:** Use a prepared account with permanent access and a separate renewing monthly subscription → Profile → Bara+.
   - **Verify:** Permanent ownership remains visible alongside the monthly management link and cancellation guidance. They do not replace or cover each other. If guidance uses a dialog, both its action and dismissal remain visible. Next-reward placement follows the approved overlap policy; its exact timing is pending that decision.

4. **Real entry points and navigation**
   - **Get there:** Visit Shop, Profile, Home → Get Coins, and Shop → an unaffordable item → Get Coins.
   - **Verify:** Shop and Profile each retain one membership card below their header. Get Coins retains one membership card after coin packs and before earning options. Each opens the updated membership screen. Profile’s badge remains beside its existing identity area. No yearly sales tile, extra tab or duplicated membership card appears; back navigation returns to the originating screen.

5. **Standalone billing preview**
   - **Get there:** Open the supplied billing-preview build → Preview Controls; select nonmember, permanent-owner and permanent-plus-monthly scenarios.
   - **Verify:** Check its Plus, Shop, Coins and Profile pages against checkpoints 1–4, including Shop → Get Coins. Annual offers are absent here too. Preview-only navigation stays confined to this build.

6. **Settings and tutorial mirrors**
   - **Get there:** Profile → Settings → View Tutorial; then Settings → View Shop Tutorial. In shop replay, open Get Coins through the coin entry and an unaffordable item where available.
   - **Verify:** Tutorial screens and nested Get Coins contain no membership sales cards or permanent offers. Existing tutorial spotlights still surround their intended elements. Settings retains its existing layout; no duplicate billing entry appears.

7. **Both platforms and constrained layouts**
   - **Get there:** Repeat the membership offer and overlapping-membership screens on iOS and Android, using the smallest available device and enlarged system text.
   - **Verify:** Options, ownership, next-reward information and cancellation guidance do not overlap. Purchase/management, restore, legal and back controls remain reachable by scrolling and clear the bottom system inset.

*Surfaces confirmed unaffected:*\
Demo race tutorial and race-detail tutorial preview: shared race screens are wrapped in disabled billing scopes; neither hosts the membership offer selector.\
Single/multiple box-opening screens and race reroll sheets: no plan-selection or ownership placement changes are proposed.\
Home, Races, Friends and leaderboard content: no membership selector is embedded; Home only routes to Get Coins.\
Production and tutorial tab bars: separate implementations exist, but neither requires a placement change.\
Settings: no existing Bara+ purchase or management tile was found; its relevant routes are tutorial replay.

*Risks found while planning:*\
Preview plans and account scenarios are hand-maintained; permanent ownership and overlapping monthly access need explicit fixtures.\
The current membership screen assumes monthly/yearly selection in several places; replacing only the offer tile can leave a yearly change-plan dialog or stale controls.\
Permanent owners with a remaining monthly subscription need both access information and management controls visible together.\
Tutorial billing-card absence is intentional here because those hosts explicitly disable billing; nested Get Coins must preserve that scope.
