const { ethers } = require("ethers");
const fs = require("fs");

function getCreationCode() {
    const artifactPath = "./Earnkit.json";
    const artifact = JSON.parse(fs.readFileSync(artifactPath, "utf8"));
  
    // Ensure we return only the bytecode as a string
    return typeof artifact.bytecode === "string" ? artifact.bytecode : artifact.bytecode.object;
  }
  

function generateSaltForAddress(
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
  // Initialize saltNum with current epoch time
  let saltNum = BigInt(Math.floor(Date.now() / 1000));
  const EarnkitTokenBytecode = getCreationCode();

  while (true) {
    const saltBytes = ethers.zeroPadValue(ethers.toBeHex(saltNum), 32);

    // Encode constructor parameters
    const constructorArgs = ethers.AbiCoder.defaultAbiCoder().encode(
      ["string", "string", "uint256", "address", "uint256", "string", "string"],
      [name, symbol, totalSupply, deployer, fid, image, castHash]
    );

    // Combine creation code and constructor args
    const bytecode = ethers.concat([EarnkitTokenBytecode, constructorArgs]);

    // Calculate the hash of the bytecode
    const bytecodeHash = ethers.keccak256(bytecode);

    // Calculate salt hash
    const saltHash = ethers.keccak256(
      ethers.AbiCoder.defaultAbiCoder().encode(["address", "bytes32"], [deployer, saltBytes])
    );

    // Compute the predicted contract address
    const predictedAddress = ethers.getCreate2Address(
      earnkitContract,
      saltHash,
      bytecodeHash
    );

    console.log("predictedAddress", predictedAddress)

    if (ethers.getBigInt(predictedAddress) < ethers.getBigInt(poolConfig.pairedToken)) {
      return saltBytes;
    }
    saltNum++;
  }
}

function main() {
  const name = "ExampleToken";
  const symbol = "EXT";
  const totalSupply = 1000000;
  const fid = 12345;
  const image = "https://example.com/token.png";
  const castHash = "0xabc123";
  const poolConfig = { pairedToken: "0x4200000000000000000000000000000000000006" };
  const deployer = "0x97861976283e6901b407D1e217B72c4007D9F64D";
  const earnkitContract = "0xdAa5AF55de378ff182fA1dE3923A475E0529608F";

  const salt = generateSaltForAddress(
    name,
    symbol,
    totalSupply,
    fid,
    image,
    castHash,
    poolConfig,
    deployer,
    earnkitContract
  );

  console.log("Generated Salt:", salt);
}

main();

module.exports = { generateSaltForAddress, main };