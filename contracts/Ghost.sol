pragma solidity 0.4.23;
pragma experimental "ABIEncoderV2";

// import "./Transfer.sol";


contract Ghost {
    // aka, "The Other Ghost Protocol"

    enum ActionType {
        SUBMIT_LETTER,
        // same player goes twice in a row:
        CHALLENGE_FULL_WORD,
        PROVE_FULL_WORD,
        CHALLENGE_PROJECTED_WORD,
        REVEAL_AND_PROVE_PROJECTED_WORD
    }

    struct Action {
        ActionType actionType;
        uint letter;
        bytes32 wordCommitHash;
        // i.e., whether you want to dispute the challenge or just concede, FOR REVEAL_AND_PROVE_PROJECTED_WORD
        bool dispute;
        uint[25] secretWord;
        bytes32 secretWordSalt;
        bytes32[] merkleProof;
        // TODO rename these...
        bool fullWordChallengeInProgress;
        bool projectedWordChallendgeInProgress;
    }

    struct AppState {
        // Q is the framework opinionated about playerAddrs?
        address[2] playerAddrs;
        uint[2] scores;
        uint[25] currentWord;
        uint currentWordLength;
        // only need the latest (i.e., can't challenge old words)
        bytes32 currentCommitHash;
        uint256 turnNum;
        bool fullWordChallengeInProgress;
        bool projectedWordChallendgeInProgress;

    }
    //(placeholder atm)
    bytes32 constant allWordsMerkleRoot= 0x12;


    function applyAction(AppState state, Action action)
    public
    pure
    returns (bytes)
  {
    AppState memory postState;
    // turn doesn't update for CHALLENGE_FULL_WORD:
     if (action.actionType == ActionType.CHALLENGE_FULL_WORD) {
      postState = challengeFullWord(state);
    } else {
        
        if (action.actionType == ActionType.SUBMIT_LETTER) {
            postState = submitLetter(state, action.letter, action.wordCommitHash);
        } else if(action.actionType == ActionType.PROVE_FULL_WORD){
            postState = proveFullWord(state, action.merkleProof);
        } else if (action.actionType == ActionType.CHALLENGE_PROJECTED_WORD){
            postState = challengeProjectedWord(state);
        } else if (action.actionType == ActionType.REVEAL_AND_PROVE_PROJECTED_WORD){
            postState = proveProjectedWord(state, action.merkleProof, action.secretWord, action.secretWordSalt);
        }
        postState.turnNum += 1;
    }
    return abi.encode(postState);
  }


    function isStateTerminal(AppState state)
        public
        pure
        returns (bool){
            return state.scores[0] == 5 || state.scores[1] == 5;
        }
    
    // Q: is this required / opinionated?
    function getTurnTaker(AppState state)
        public
        pure
        returns (uint256)
    {
        return state.turnNum % 2;
    }

    function submitLetter(AppState state, uint letter, bytes32 wordCommitHash)
        internal
        pure 
        assertNoChallenge(state)
        returns (AppState) {
            withinAsciiRange(letter);
            state.currentCommitHash = wordCommitHash;
            uint256 newIndex = state.currentWordLength + 1;
            state.currentWord[newIndex] = letter;
        
            state.currentWordLength = newIndex;
            return state;
        }

    function challengeFullWord(AppState state)
        internal
        pure 
        assertNoChallenge(state)
        returns (AppState){
            require(state.turnNum > 6);
            state.fullWordChallengeInProgress = true;
            return state;
        }
    function proveFullWord(AppState state, bytes32[] merkleProof)
        internal
        pure
        returns (AppState)
        {
        AppState memory postState;
        assert(state.fullWordChallengeInProgress);
        // TODO get just world itsef as uint[]
        if (merkleVerify( state.currentWord, merkleProof)){
            postState = currentPlayerWinsRound(state);
        } else {
            postState = otherPlayerWinsRound(state);
        }
        return postState;
    }
    

    function challengeProjectedWord(AppState state)
        internal
        pure
        assertNoChallenge(state)
        returns(AppState){
            state.projectedWordChallendgeInProgress = true;
            return state;
        }

    function proveProjectedWord(AppState state, bytes32[] merkleProof, uint[25] secretWord, bytes32 secretWordSalt)
        internal
        pure
        returns(AppState)
        {
        assert(state.projectedWordChallendgeInProgress);
        bytes32 generatedHash = keccak256(abi.encodePacked(secretWord, secretWordSalt));
        // check that secret staRts with right letters
        uint currentLetter;
        for (uint256 i = 0; i < 25; i++) {
            currentLetter = state.currentWord[i];
            if(currentLetter==0) break;
            if (currentLetter != secretWord[i]){
                 return otherPlayerWinsRound(state); 
            }
        }
        
        if (generatedHash != state.currentCommitHash || !merkleVerify(secretWord, merkleProof) ){
            return otherPlayerWinsRound(state);
        } else {
            return currentPlayerWinsRound(state);
        }
    }
    
    function currentPlayerWinsRound(AppState state)
        internal
        pure
        returns(AppState)
    {
     state.scores[getTurnTaker(state)] += 1;
     return startNewRound(state);   
    }

    function otherPlayerWinsRound(AppState state)
        internal
        pure
        returns(AppState)
    {
     state.scores[(getTurnTaker(state)+1) % 2] += 1;
     return startNewRound(state);   
    }

    function startNewRound(AppState state)
        internal
        pure
        returns (AppState){
            uint[25] memory newArr;
            state.currentWord = newArr;
            state.currentCommitHash = "";
            state.fullWordChallengeInProgress = false;
            state.projectedWordChallendgeInProgress = false;
            // alternate starting player each round
            state.turnNum = (state.scores[0] + state.scores[1]) % 2;
            return state;
        }

    // incorporated from https://github.com/omisego/plasma-contracts/blob/master/contracts/Merkle.sol
    function merkleVerify(uint[25] content, bytes32[] proof)
        internal
        pure 
        returns (bool){
            bytes32 root = allWordsMerkleRoot;

            //TODO: abi encode content??
            bytes32 computedHash = keccak256(content);
            for (uint256 i = 0; i < proof.length; i++) {
                bytes32 proofElement = proof[i];

                if (computedHash < proofElement) {
                 // Hash(current computed hash + current element of the proof)
                    computedHash = keccak256(abi.encodePacked(computedHash, proofElement));
                } else {
                // Hash(current element of the proof + current computed hash)
                computedHash = keccak256(abi.encodePacked(proofElement, computedHash));
                }
             }
      // Check if the computed hash (root) is equal to the provided root
        return computedHash == root;
    }
       
     modifier assertNoChallenge(AppState state) {
        assert(!state.fullWordChallengeInProgress && !state.projectedWordChallendgeInProgress);
        _;
         
     }
     
     function withinAsciiRange(uint num) pure internal {
         assert(num >= 97 && num <=122);
     }

// TODO:
//   function resolve(AppState state, Transfer.Terms terms)
//     public
//     pure
//     returns (Transfer.Transaction){
//       return Transfer.Transaction(
//         terms.assetType,
//         terms.token,
//         to,
//         amounts,
//         data
//       );
//     }
        


}