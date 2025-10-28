#!/bin/bash
set -e

echo "================================================"
echo "Homelab v2 - Export Root CA"
echo "================================================"

OUTPUT_FILE="homelab-root-ca.crt"

# Extract root CA certificate from secret
echo "Extracting root CA certificate..."
kubectl get secret root-ca-secret -n cert-manager -o jsonpath='{.data.tls\.crt}' | base64 -d > "$OUTPUT_FILE"

if [ -f "$OUTPUT_FILE" ]; then
    echo ""
    echo "✅ Root CA certificate exported to: $OUTPUT_FILE"
    echo ""
    echo "Next steps:"
    echo ""
    echo "Mac:"
    echo "1. Copy certificate to Mac: scp $OUTPUT_FILE jon@<mac-ip>:~/Downloads/"
    echo "2. Open Keychain Access"
    echo "3. Import to System keychain"
    echo "4. Set trust to 'Always Trust'"
    echo ""
    echo "Windows:"
    echo "1. Copy to Windows: wsl cat ~/$OUTPUT_FILE > \$env:USERPROFILE\\Downloads\\$OUTPUT_FILE"
    echo "2. Run as Administrator:"
    echo "   Import-Certificate -FilePath \"\$env:USERPROFILE\\Downloads\\$OUTPUT_FILE\" -CertStoreLocation Cert:\\LocalMachine\\Root"
    echo ""
else
    echo "❌ Failed to export root CA certificate"
    exit 1
fi
