#!/usr/bin/env python3
"""Exercise ricochet-send with an isolated bitcoin-cli mock; never contact a node."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
from decimal import Decimal

ROOT = Path(__file__).resolve().parents[1]
ADDRESS = '1BoatSLRHtKNngkdXEeobR76b53LETtpyT'

MOCK = r'''#!/usr/bin/env python3
import json
import os
from pathlib import Path
import sys

state = Path(os.environ['MOCK_STATE'])
args = sys.argv[1:]
with (state / 'calls').open('a') as log:
    log.write(json.dumps(args) + '\n')
while args and args[0].startswith('-'):
    args.pop(0)
method, *args = args
if method == 'getwalletinfo':
    print('{}')
elif method == 'getmempoolinfo':
    print(json.dumps({'mempoolminfee': float(os.environ['MEMPOOL_FEE'])}))
elif method == 'estimatesmartfee':
    print('{"feerate":0.00002000}')
elif method == 'getnewaddress':
    print('1BoatSLRHtKNngkdXEeobR76b53LETtpyT')
elif method == 'sendtoaddress':
    params = dict(arg.split('=', 1) for arg in args)
    assert set(params) == {'address', 'amount', 'fee_rate'}, params
    (state / 'payment').write_text(json.dumps(params))
    print('mock-txid')
elif method == 'getrawtransaction':
    print('mock-raw')
elif method == 'decoderawtransaction':
    params = json.loads((state / 'payment').read_text())
    print(json.dumps({'txid': 'mock-txid', 'vout': [{
        'value': 'AMOUNT_PLACEHOLDER', 'scriptPubKey': {
            'address': params['address'], 'hex': '76a91400'}}]}).replace(
            '"AMOUNT_PLACEHOLDER"', params['amount']))
elif method == 'createrawtransaction':
    print('mock-raw')
elif method == 'dumpprivkey':
    print('mock-key')
elif method == 'signrawtransactionwithkey':
    print('{"hex":"mock-signed"}')
elif method == 'sendrawtransaction':
    print('mock-txid')
else:
    sys.exit('Unexpected RPC: ' + method)
'''


class RicochetSendTests(unittest.TestCase):
    def run_script(self, fee='0.00002000', factor='0.3', minimum='0.00001000', hops=1):
        with tempfile.TemporaryDirectory() as directory:
            work = Path(directory)
            for name in ('ricochet-send.sh', 'inc.common.sh', 'estimatesmartfee.sh'):
                shutil.copy2(ROOT / name, work / name)
            # Record the real random selections, including their original units.
            with (work / 'inc.common.sh').open('a') as common:
                common.write('''
eval "$(declare -f randamount | sed '1s/randamount/original_randamount/')"
randamount() {
    local selected
    selected="$(original_randamount "$@")"
    echo "$1 $2 $selected" >> "$MOCK_STATE/draws"
    echo "$selected"
}
''')
            cli = work / 'bitcoin-cli'
            cli.write_text(MOCK)
            cli.chmod(0o755)
            env = dict(os.environ, PATH=str(work) + os.pathsep + os.environ['PATH'],
                       MOCK_STATE=str(work), MEMPOOL_FEE=minimum)
            result = subprocess.run(
                ['bash', str(work / 'ricochet-send.sh'), '-rpcwallet=test-wallet',
                 '1', ADDRESS, str(hops), fee, '0', '1', '0', factor],
                input='y\n', text=True, capture_output=True, env=env, timeout=20)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            calls = [json.loads(line) for line in (work / 'calls').read_text().splitlines()]
            sends = [call for call in calls if 'sendtoaddress' in call]
            self.assertEqual(len(sends), 1)
            self.assertEqual(sends[0][:3], ['-rpcwallet=test-wallet', '-named', 'sendtoaddress'])
            self.assertFalse(any('settxfee' in call for call in calls))
            params = dict(arg.split('=', 1) for arg in sends[0][3:])
            draws = [[Decimal(x) for x in line.split()]
                     for line in (work / 'draws').read_text().splitlines()]
            self.assertEqual(len(draws), hops)
            self.assertEqual(Decimal(params['fee_rate']), draws[0][2] * 100000)
            self.assertEqual(params['address'], ADDRESS)
            self.assertEqual(Decimal(params['amount']), Decimal(1) + sum(d[2] for d in draws[1:]))
            for low, high, selected in draws:
                self.assertGreaterEqual(selected, low)
                self.assertLessEqual(selected, high)
            return params, draws, calls

    def test_exact_conversion_without_variance(self):
        for fee, expected in [('0.00002000', '2'), ('0.00001234', '1.234'),
                              ('0.00000001', '0.001')]:
            with self.subTest(fee=fee):
                params, _, _ = self.run_script(fee, '0', '0.00000001')
                self.assertEqual(Decimal(params['fee_rate']), Decimal(expected))

    def test_randomized_fee_and_hop_funding(self):
        for _ in range(5):
            _, draws, calls = self.run_script(hops=3)
            self.assertTrue(all(d[:2] == [Decimal('0.000014'), Decimal('0.000026')]
                                for d in draws))
            self.assertEqual(sum('sendrawtransaction' in c for c in calls), 2)

    def test_mempool_floor(self):
        _, draws, _ = self.run_script(minimum='0.00001900')
        self.assertEqual(draws[0][:2], [Decimal('0.000019'), Decimal('0.000026')])

    def test_custom_variance(self):
        _, draws, _ = self.run_script(factor='0.2')
        self.assertEqual(draws[0][:2], [Decimal('0.000016'), Decimal('0.000024')])

    def test_estimated_fee(self):
        params, _, calls = self.run_script(fee='', factor='0')
        self.assertTrue(any('estimatesmartfee' in c for c in calls))
        self.assertEqual(Decimal(params['fee_rate']), Decimal(2))


if __name__ == '__main__':
    unittest.main()
