const { ethers } = require("ethers");
const dotenv = require("dotenv");
const EarnkitABI = require("./Earnkit.json");
const fs = require("fs");

dotenv.config();

const PROVIDER_URL = process.env.RPC_URL;
const PRIVATE_KEY = process.env.PRIVATE_KEY;
const EARNKIT_CONTRACT = process.env.EARNKIT_CONTRACT_ADDRESS;

const WETH = "0x4200000000000000000000000000000000000006";
const FEE = 10000;
const TICK = -230400;

function getCreationCode() {
    const artifactPath = "./EarnkitToken.json";
    const artifact = JSON.parse(fs.readFileSync(artifactPath, "utf8"));
  
    // Ensure we return only the bytecode as a string
    return typeof artifact.bytecode === "string" ? artifact.bytecode : artifact.bytecode.object;
  }

async function generateSaltForAddress(
    name,
    symbol,
    totalSupply,
    fid,
    image,
    castHash,
    poolConfig,
    deployer,
    earnkitContract
) {
    const provider = new ethers.JsonRpcProvider(PROVIDER_URL);
    const blockNumber = await provider.getBlockNumber();
    const block = await provider.getBlock(blockNumber - 1);
    
    // Initialize saltNum with block hash
    let saltNum = BigInt(block.hash);
    const EarnkitTokenBytecode = getCreationCode();

    while (true) {
        try {
            const saltBytes = ethers.zeroPadValue(ethers.toBeHex(saltNum), 32);

            // Encode constructor parameters
            const constructorArgs = ethers.AbiCoder.defaultAbiCoder().encode(
                ["string", "string", "uint256", "address", "uint256", "string", "string"],
                [name, symbol, totalSupply, deployer, fid, image, castHash]
            );

            // Combine creation code and constructor args
            const bytecode = ethers.solidityPacked(
                ["bytes", "bytes"],
                [EarnkitTokenBytecode, constructorArgs]
            );

            // Calculate the hash of the bytecode
            const bytecodeHash = ethers.keccak256(bytecode);
            console.log(bytecodeHash)

            // Calculate salt hash using the correct format
            const saltHash = ethers.keccak256(
                ethers.concat([
                    ethers.zeroPadValue(deployer, 32),
                    saltBytes
                ])
            );

            // Compute the predicted address
            const predictedAddress = ethers.getCreate2Address(
                earnkitContract,
                saltHash,
                bytecodeHash
            );

            // Convert addresses to checksummed format for comparison
            const predictedAddressChecksummed = ethers.getAddress(predictedAddress);
            const pairedTokenChecksummed = ethers.getAddress(poolConfig.pairedToken);

            console.log("Trying salt:", saltBytes);
            console.log("Predicted address:", predictedAddressChecksummed);
            console.log("Paired token:", pairedTokenChecksummed);

            // Compare addresses lexicographically
            if (predictedAddressChecksummed.toLowerCase() < pairedTokenChecksummed.toLowerCase()) {
                console.log("Found valid salt:", saltBytes);
                return saltBytes;
            }

            saltNum++;
        } catch (error) {
            console.error("Error in salt generation:", error);
            saltNum++;
        }
    }
}

async function main() {
    const provider = new ethers.JsonRpcProvider(PROVIDER_URL);
    const wallet = new ethers.Wallet(PRIVATE_KEY, provider);
    const earnkit = new ethers.Contract(EARNKIT_CONTRACT, EarnkitABI.abi, wallet);

    const name = "Sarvagna";
    const symbol = "SKK";
    const totalSupply = ethers.parseUnits("100000000000", 18);
    const fid = 884823;
    const image = "https://sarvagna.sqrtlabs.com/assets/1-9c390b40.png";
    const castHash = "0x9ecb8361a98711a1ecf36d8fbc391d1af9140ded";

    const poolConfig = {
        pairedToken: WETH,
        devBuyFee: FEE,
        tick: TICK
    };

    const salt = await generateSaltForAddress(
        name, 
        symbol, 
        totalSupply, 
        fid, 
        image, 
        castHash, 
        poolConfig, 
        wallet.address, 
        EARNKIT_CONTRACT
    );

    console.log("Generated salt:", salt);

    const campaigns = [
        {
            maxClaims: 100,
            amountPerClaim: ethers.parseUnits("50000000", 18),
            maxSponsoredClaims: 0
        },
        {
            maxClaims: 200,
            amountPerClaim: ethers.parseUnits("25000000", 18),
            maxSponsoredClaims: 0
        }
    ];

    console.log("Deploying token with campaigns...");
    const tx = await earnkit.deployTokenWithCampaigns(
        name,
        symbol,
        totalSupply,
        FEE,
        salt,
        wallet.address,
        fid,
        image,
        castHash,
        poolConfig,
        campaigns,
        10,
    );

    console.log("Transaction sent. Waiting for confirmation...");
    const receipt = await tx.wait();
    console.log("Transaction confirmed:", receipt.hash);

    // Extract deployed token address from logs
    const tokenAddress = receipt.logs[0]?.address;
    console.log("Token deployed at:", tokenAddress);
}

main().catch((error) => {
    console.error("Error deploying token:", error);
    process.exit(1);
});
