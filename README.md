# 🎨 Digital Licensing Platform Smart Contract 🎵

A decentralized platform for managing digital art and music licenses using NFTs on the Stacks blockchain.

## 🌟 Features

- Create digital licenses with customizable terms
- Purchase licenses with automatic royalty distribution
- Transfer licenses (if allowed by creator)
- Track creator royalties
- IPFS integration for content storage

## 📚 Contract Functions

### For Creators
- `create-license`: Mint new license NFTs for digital content
- `get-creator-royalties`: Check accumulated royalties

### For Buyers
- `purchase-license`: Buy usage rights for digital content
- `transfer-license`: Transfer owned licenses
- `get-license-details`: View license information

## 🔧 Usage

1. Deploy the contract to the Stacks blockchain
2. Create licenses by providing:
   - IPFS hash of the content
   - License price
   - Usage type
   - Transfer permissions
3. Buyers can purchase licenses using STX
4. Automatic royalty distribution on each sale

## 💡 Example

```clarity
;; Create a new music license
(contract-call? .digital-licensing create-license "QmHash..." u1000 "commercial" true)

;; Purchase a license
(contract-call? .digital-licensing purchase-license u1)
```

## 🔒 Security

- Built-in ownership verification
- Automated royalty payments
- Transfer restrictions
- Permanent license records
```

