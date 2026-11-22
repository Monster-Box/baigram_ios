import base64
import datetime
import os
import plistlib
import shutil
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from BuildEnvironment import run_executable_with_output
from GenerateProfiles import setup_temp_keychain, cleanup_temp_keychain

# The bundled fake-codesigning profiles carry a fixed ExpirationDate. Once that
# date passes Bazel rejects them ("provisioning profile ExpirationDate is in the
# past"), so this rebuilds every profile with a long-lived date and signs it
# again with the self-signed certificate. The output directory has the
# "profiles/" + "certs/" layout that --codesigningInformationPath expects.


def find_signing_identity(keychain_name):
    output = run_executable_with_output('security', arguments=['find-identity', '-v', '-p', 'codesigning', keychain_name], check_result=True)
    for line in output.splitlines():
        if '"' in line:
            return line.split('"')[1]
    return None


def certificate_der_bytes(keychain_name, identity):
    pem = run_executable_with_output('security', arguments=['find-certificate', '-c', identity, '-p', '-k', keychain_name], check_result=True)
    body = ''.join(line for line in pem.splitlines() if not line.startswith('-----'))
    return base64.b64decode(body)


def main():
    base_path = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    source_profiles = os.path.join(base_path, 'build-system', 'fake-codesigning', 'profiles')
    source_certs = os.path.join(base_path, 'build-system', 'fake-codesigning', 'certs')
    destination = sys.argv[1] if len(sys.argv) > 1 else os.path.join(base_path, 'build', 'verification-codesigning')

    destination_profiles = os.path.join(destination, 'profiles')
    destination_certs = os.path.join(destination, 'certs')
    if os.path.isdir(destination):
        shutil.rmtree(destination)
    os.makedirs(destination_profiles)
    shutil.copytree(source_certs, destination_certs)

    p12_path = os.path.join(source_certs, 'SelfSigned.p12')
    keychain_name = setup_temp_keychain(p12_path, '')
    try:
        signing_identity = find_signing_identity(keychain_name)
        if not signing_identity:
            print('Could not find the signing identity in {}'.format(p12_path))
            sys.exit(1)
        certificate_data = certificate_der_bytes(keychain_name, signing_identity)

        expiration = datetime.datetime(2035, 1, 1, 0, 0, 0)
        for file_name in sorted(os.listdir(source_profiles)):
            if not file_name.endswith('.mobileprovision'):
                continue

            source_path = os.path.join(source_profiles, file_name)
            plist_text = run_executable_with_output('security', arguments=['cms', '-D', '-i', source_path], check_result=True)
            profile = plistlib.loads(plist_text.encode('utf-8'))

            profile['ExpirationDate'] = expiration
            profile['DeveloperCertificates'] = [certificate_data]
            profile.pop('DER-Encoded-Profile', None)

            temp_path = tempfile.mktemp(suffix='.plist')
            with open(temp_path, 'wb') as file:
                plistlib.dump(profile, file)

            destination_path = os.path.join(destination_profiles, file_name)
            run_executable_with_output('security', arguments=[
                'cms', '-S', '-k', keychain_name, '-N', signing_identity,
                '-i', temp_path, '-o', destination_path
            ], check_result=True)
            os.unlink(temp_path)
            print('Refreshed {}'.format(file_name))
    finally:
        cleanup_temp_keychain(keychain_name)


if __name__ == '__main__':
    main()
