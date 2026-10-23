# Security patch: strip compromised CA roots from awscli2's vendored bundle.
#
# aws/aws-cli@c044a7c (v2.38.4, 2026-10-21) removed the "Comodo AAA Services"
# root and the four eMudhra/emSign roots whose signing keys were compromised.
# Our pinned nixpkgs ships an older awscli2 that still bundles them.
#
# This overlay patches the installed cacert.pem in postFixup so every host
# that imports it gets the fix without bumping the entire awscli2 derivation.
#
# Remove this overlay once nixpkgs ships awscli2 >= 2.38.4.
_final: prev: {
  awscli2 = prev.awscli2.overridePythonAttrs (old: {
    postFixup =
      (old.postFixup or "")
      + ''
        # --- CVE: strip compromised CA certs from vendored bundle ---
        find $out -name 'cacert.pem' -path '*/botocore/cacert.pem' | while read -r pem; do
          ${prev.python3}/bin/python3 - "$pem" <<'PYEOF'
import sys, re

pem_path = sys.argv[1]
with open(pem_path) as f:
    content = f.read()

# Labels in botocore's cacert.pem use: # Label: "Name"
remove = {
    "Comodo AAA Services root",
    "emSign Root CA - C1",
    "emSign Root CA - G1",
    "emSign ECC Root CA - C3",
    "emSign ECC Root CA - G3",
}

# Each cert block: blank line, then # Issuer/Subject/Label/Serial/fingerprint
# metadata lines, then the PEM data.
# Match from the blank-line boundary through -----END CERTIFICATE-----.
pattern = re.compile(
    r'\n{1,2}(# Issuer:.*?# Label: "([^"]+)".*?-----END CERTIFICATE-----)',
    re.DOTALL,
)

removed = []
def replacer(m):
    label = m.group(2).strip()
    if label in remove:
        removed.append(label)
        return ""
    return m.group(0)

patched = pattern.sub(replacer, content)

if removed:
    with open(pem_path, 'w') as f:
        f.write(patched)
    print(f"awscli2-ca-fix: removed {len(removed)} certs: {', '.join(removed)}")
else:
    print("awscli2-ca-fix: none of the targeted certs found (already clean)")
PYEOF
        done
      '';
  });
}
