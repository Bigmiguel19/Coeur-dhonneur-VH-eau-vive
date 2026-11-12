// Run: node --experimental-vm-modules --test scripts/phone-auth.test.mjs
// All authentication calls below are mocks. No hosted services are contacted.
import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import vm from "node:vm";

const root = new URL("../", import.meta.url);
const utilsSource = await readFile(new URL("assets/js/utils.js", root), "utf8");
const authSource = await readFile(new URL("assets/js/auth.js", root), "utf8");
const { normalizePhone, isValidPassword } = await import(
  `data:text/javascript;base64,${Buffer.from(utilsSource).toString("base64")}`
);

const validPhones = [
  ["0700000000", "+2250700000000"],
  [" 07 00 00 00 00 ", "+2250700000000"],
  ["01.23.45.67.89", "+2250123456789"],
  ["+2250700000000", "+2250700000000"],
  ["00225 07 00 00 00 00", "+2250700000000"],
  ["+33 1 23 45 67 89", "+33123456789"],
  ["0033123456789", "+33123456789"],
  ["+1 (202) 555-0123", "+12025550123"],
];
for (const [input, expected] of validPhones) {
  test(`phone normalization: ${input}`, () => assert.equal(normalizePhone(input), expected));
}
for (const input of [null, undefined, "", " ", "abc0700000000", "07/00/00/00/00", "++2250700000000", "+225+0700000000", "+01234567890", "+22507000000", "+22507000000000", "123456789", "2250700000000", "+1234567890123456", "00+33123456789", "0700000000ext1"]) {
  test(`invalid phone: ${String(input)}`, () => assert.equal(normalizePhone(input), null));
}

test("password boundaries and no trimming", () => {
  assert.equal(isValidPassword("abcdef1"), false);
  assert.equal(isValidPassword("abcdef12"), true);
  assert.equal(isValidPassword("abcdefgh"), false);
  assert.equal(isValidPassword("12345678"), false);
  assert.equal(isValidPassword(" abcdef1"), true);
  assert.equal(isValidPassword(null), false);
});

async function loadAuth(options = {}) {
  const calls = [];
  const user = { id: "test-member", phone: "2250700000000" };
  const session = { user, access_token: "test-only-not-a-real-token" };
  const profile = { id: user.id, full_name: "Membre", email: null, phone: "+2250700000000", role: "member", is_active: true };
  const client = {
    auth: {
      async signUp(payload) {
        calls.push(["signup", payload]);
        if (options.throwNetwork) throw new Error("Failed to fetch");
        return options.authResult ?? { data: { user, session }, error: null };
      },
      async signInWithPassword(payload) {
        calls.push(["login", payload]);
        return options.authResult ?? { data: { user, session }, error: null };
      },
      async signOut(payload) { calls.push(["signout", payload]); return { error: null }; },
    },
    from(table) {
      calls.push(["from", table]);
      return {
        select() { return this; },
        eq(column, value) { calls.push(["eq", column, value]); return this; },
        async maybeSingle() {
          return options.profileResult ?? { data: profile, error: null };
        },
      };
    },
  };
  const context = vm.createContext({ console });
  const module = new vm.SourceTextModule(authSource, { context });
  await module.link((specifier) => {
    const exports = specifier.endsWith("supabase-client.js")
      ? { supabase: client, CONFIG_ERROR: "Not configured", IS_CONFIGURED: options.configured !== false }
      : { normalizePhone, isValidPassword };
    return new vm.SyntheticModule(Object.keys(exports), function () {
      for (const [key, value] of Object.entries(exports)) this.setExport(key, value);
    }, { context });
  });
  await module.evaluate();
  return { auth: module.namespace, calls, profile };
}

test("signup sends only native phone/password and waits for a usable profile", async () => {
  const { auth, calls } = await loadAuth();
  const result = await auth.registerWithPhone("07 00 00 00 00", " abcdef1");
  assert.equal(result.error, null);
  assert.equal(result.profile.email, null);
  assert.equal(result.profile.role, "member");
  assert.equal(calls[0][0], "signup");
  assert.equal(calls[0][1].phone, "+2250700000000");
  assert.equal(calls[0][1].password, " abcdef1");
  assert.deepEqual(Object.keys(calls[0][1]).sort(), ["password", "phone"]);
  assert.ok(calls.some(([action]) => action === "from"));
});

test("invalid registration never calls the auth API", async () => {
  const { auth, calls } = await loadAuth();
  assert.ok((await auth.registerWithPhone("bad", "abcdef12")).error);
  assert.ok((await auth.registerWithPhone("0700000000", "weak")).error);
  assert.equal(calls.length, 0);
});

test("phone and legacy email login retain distinct credential payloads", async () => {
  const { auth, calls } = await loadAuth();
  assert.equal((await auth.signIn("0700000000", "abcdef12", "phone")).error, null);
  assert.equal((await auth.signIn(" ADMIN@EXAMPLE.COM ", "abcdef12", "email")).error, null);
  const logins = calls.filter(([action]) => action === "login");
  assert.equal(logins[0][1].phone, "+2250700000000");
  assert.equal(logins[0][1].email, undefined);
  assert.equal(logins[1][1].email, "admin@example.com");
  assert.equal(logins[1][1].phone, undefined);
});

for (const code of ["phone_exists", "signup_disabled", "phone_provider_disabled", "over_request_rate_limit", "invalid_credentials"]) {
  test(`auth failure: ${code}`, async () => {
    const { auth } = await loadAuth({ authResult: { data: null, error: { code, message: code } } });
    const result = await auth.registerWithPhone("0700000000", "abcdef12");
    assert.equal(result.session, null);
    assert.equal(result.error.code, code);
    assert.notEqual(auth.authErrorMessage(result.error), code);
  });
}

test("network failure produces a recoverable error", async () => {
  const { auth } = await loadAuth({ throwNetwork: true });
  const result = await auth.registerWithPhone("0700000000", "abcdef12");
  assert.equal(result.session, null);
  assert.match(auth.authErrorMessage(result.error), /Connexion au serveur impossible/);
});

test("signup without session never reports success", async () => {
  const { auth, calls } = await loadAuth({ authResult: { data: { user: { id: "test-member" }, session: null }, error: null } });
  const result = await auth.registerWithPhone("0700000000", "abcdef12");
  assert.equal(result.session, null);
  assert.match(result.error.message, /Aucune session/);
  assert.equal(calls.filter(([action]) => action === "from").length, 0);
});

for (const data of [null, { id: "test-member", is_active: false, role: "member" }]) {
  test(`missing or suspended profile fails closed: ${data === null ? "missing" : "suspended"}`, async () => {
    const { auth, calls } = await loadAuth({ profileResult: { data, error: null } });
    const result = await auth.signIn("0700000000", "abcdef12", "phone");
    assert.equal(result.session, null);
    assert.ok(result.error);
    assert.ok(calls.some(([action, payload]) => action === "signout" && payload.scope === "local"));
  });
}

for (const file of ["register.html", "login.html", "profile.html", "forgot-password.html", "admin/index.html", "admin/members.html", "admin/arrears.html"]) {
  test(`inline module syntax: ${file}`, async () => {
    const html = await readFile(new URL(file, root), "utf8");
    const modules = [...html.matchAll(/<script\s+type="module">([\s\S]*?)<\/script>/g)];
    assert.ok(modules.length > 0);
    for (const [, source] of modules) new vm.SourceTextModule(source);
  });
}
