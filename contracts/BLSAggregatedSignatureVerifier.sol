pragma solidity ^0.8.17;

import "./libraries/Pairing.sol";

/*
* @author https://github.com/succinctlabs/eth-proof-of-consensus
*/
contract BLSAggregatedSignatureVerifier {
	struct SignatureVerifyingKey {
		Pairing.G1Point alfa1;
		Pairing.G2Point beta2;
		Pairing.G2Point gamma2;
		Pairing.G2Point delta2;
		Pairing.G1Point[] IC;
	}
	struct SignatureProof {
		Pairing.G1Point A;
		Pairing.G2Point B;
		Pairing.G1Point C;
	}

	function signatureVerifyingKey() internal pure returns (SignatureVerifyingKey memory vk) {
		vk.alfa1 = Pairing.G1Point(
			20491192805390485299153009773594534940189261866228447918068658471970481763042,
			9383485363053290200918347156157836566562967994039712273449902621266178545958
		);

		vk.beta2 = Pairing.G2Point(
			[
				4252822878758300859123897981450591353533073413197771768651442665752259397132,
				6375614351688725206403948262868962793625744043794305715222011528459656738731
			],
			[
				21847035105528745403288232691147584728191162732299865338377159692350059136679,
				10505242626370262277552901082094356697409835680220590971873171140371331206856
			]
		);
		vk.gamma2 = Pairing.G2Point(
			[
				11559732032986387107991004021392285783925812861821192530917403151452391805634,
				10857046999023057135944570762232829481370756359578518086990519993285655852781
			],
			[
				4082367875863433681332203403145435568316851327593401208105741076214120093531,
				8495653923123431417604973247489272438418190587263600148770280649306958101930
			]
		);
		vk.delta2 = Pairing.G2Point(
			[
				19544391387317795908693780671452630021663160678150576511879734045746142668848,
				6917808035996032566040803443721470868926922971971642817023919900006732873381
			],
			[
				6550171645782704964138654851739795195039536923577535566774725931353550994141,
				17393513049111511759089475614971590118089378704580429368956333521504553853058
			]
		);
		vk.IC = new Pairing.G1Point[](35);

		vk.IC[0] = Pairing.G1Point(
			18634118167700065378232596069078433146864186665994201555961864106828086212743,
			14327951947179588742006969851213165520573615742149483260977723763469755404423
		);

		vk.IC[1] = Pairing.G1Point(
			15754604637577586343855596062581148391677160532391566684762128622210125145440,
			12029005404042902409069827689906205461731520076403261203730735303034406022756
		);

		vk.IC[2] = Pairing.G1Point(
			21032409925079266628115888414096993511961789777319711219129621190601000507660,
			13933503379131448514796295579902114318122487497247387979458794020094809911104
		);

		vk.IC[3] = Pairing.G1Point(
			1030042835797972600594323310675301872182264017081174020071332351641809409007,
			13035448255249303627598987990625684481866267923428463242624104913232400097513
		);

		vk.IC[4] = Pairing.G1Point(
			9205408164696378067540737009060653196285105141293830253413405594461158039458,
			10960004037751317217256013767425610585307403138124264170732581854842770608394
		);

		vk.IC[5] = Pairing.G1Point(
			12808276965221917931313922702084614292956235169298642905447261678538693982852,
			7558982779621560965367095688635585665399234927736610476959408220124011476536
		);

		vk.IC[6] = Pairing.G1Point(
			18459679565761478196250968176684853212804968504223381818968571428065944660110,
			2096872097952952095456973150379834398657109907224273419647237262157351917134
		);

		vk.IC[7] = Pairing.G1Point(
			3138634970732559227666222492437209244756011174974646917186607109713783603997,
			2192720049506924809734330479182806865555745249881019907648097710916397964924
		);

		vk.IC[8] = Pairing.G1Point(
			11758807484997752880168338308401891371043191265251735588003479561140014849990,
			21810430338761041127707001892904268719611411963024987167007850855735597382394
		);

		vk.IC[9] = Pairing.G1Point(
			1974624120621043205397758421918060884068257519777161751738543110058854398521,
			2783553824526800129095703199611940790520079941665351782403134784060633217309
		);

		vk.IC[10] = Pairing.G1Point(
			19629520579521668793841741321108003062626145416923320320789458631976956111306,
			11939015579457581504670694629719518980562993581930813873881590957854558784118
		);

		vk.IC[11] = Pairing.G1Point(
			10128850155763913966657962625702772086757857092065338369547276800748209908063,
			2002169034914114511176648818452803888796289976033686843507860377310828433437
		);

		vk.IC[12] = Pairing.G1Point(
			7411608744245654461426763572974876442832965660867744155395989970041029240691,
			11401425095998897302203923692141483276086130599787360499398565448821914182110
		);

		vk.IC[13] = Pairing.G1Point(
			20249353995817175849257990699025532537133900476695053074484720580718225039137,
			16711623145402519134601580685702628131430816485088038784262687383926529720585
		);

		vk.IC[14] = Pairing.G1Point(
			7053195556903729121230642915833823049269955000301071215370367588203935812806,
			4117472005341969771542436076061266968804131112741010298556066985810212750745
		);

		vk.IC[15] = Pairing.G1Point(
			14972684418861233751300276878366025217056036005346922814012935600279200063930,
			5797211998574235975937878193772694374837345350210831033732828769132449316066
		);

		vk.IC[16] = Pairing.G1Point(
			10168340555928315801741170296171140542152269035790061396969709710895364324983,
			6488881150283828286772764329336908350552099315886689612527165979847221522499
		);

		vk.IC[17] = Pairing.G1Point(
			8074655797691670906723779330378657589730354366433375563181562887616106120480,
			20838889069022180450380156714155140552946596984471337869034484276117659871005
		);

		vk.IC[18] = Pairing.G1Point(
			14062849752257633212930745337184610300442015336924223314210636872927737888225,
			13434495196738875479924221794803120031346464785369463508831640483069853026272
		);

		vk.IC[19] = Pairing.G1Point(
			8804037760022290100930246659214600158696635580696690969961635779306785613253,
			1024556133937631446000370551558136872691944464703396976713502173864823030608
		);

		vk.IC[20] = Pairing.G1Point(
			15021627748420420574213012835326190684214628192687383162295239494594309359855,
			19920734802489688371046120677543374795959321408501121592932228348239507449182
		);

		vk.IC[21] = Pairing.G1Point(
			5964698091228516413942524182792784660716925306912876145997607999348175273299,
			21308102562176866266731874074069237859894193860174870735409463074245666519273
		);

		vk.IC[22] = Pairing.G1Point(
			12595148632118443666232557615135356493193609110095429858714122965253086956522,
			13834396977073151542482231671203263742309765754852367709209354947738402536193
		);

		vk.IC[23] = Pairing.G1Point(
			6122189287921052333517287478292717410627060207736858731331616350897084949821,
			11865533243689375214111781184183839763778624644755858028210789249674682454801
		);

		vk.IC[24] = Pairing.G1Point(
			11505000294160917504974393086777044729344938621403397389074873577020997258033,
			14491961248708386718582811513697614399611771036273423753715524429941305787082
		);

		vk.IC[25] = Pairing.G1Point(
			4537557171882277471478608405426830033657501077057120423708775724582636889251,
			21007631822226332326199623899948648887454065853364008833318091203422106731095
		);

		vk.IC[26] = Pairing.G1Point(
			4277037076063313313215074776251925586419611120124122071691309806491084385899,
			8070708590466632492189009088744239574260015597265171400415923170205001896996
		);

		vk.IC[27] = Pairing.G1Point(
			16406421894802611332897660905273223718640561016301122555735411114606705677692,
			21655714962765883720020178971359192536419104812052655005152336320920605699103
		);

		vk.IC[28] = Pairing.G1Point(
			12332914946105198794018470917418954042192469977939229084155256020215049332432,
			8696770130392300711807863035052299921839591486978712475628536084325694658224
		);

		vk.IC[29] = Pairing.G1Point(
			5777645844124992644782183274971501298359745088661023005413737193098258297370,
			10441067234645698583104980147672297261027649043149667565146311980468317275956
		);

		vk.IC[30] = Pairing.G1Point(
			8405762912527403184358535390807982299030192026167858927777843968719513809381,
			7206465999602998544668690435579211071227472979759299983575201549199854579197
		);

		vk.IC[31] = Pairing.G1Point(
			8154264974309719802897575848020350300005429085920656115492064898085867204501,
			7403361736707208656607041290602933317451704762234760706498987825908338573106
		);

		vk.IC[32] = Pairing.G1Point(
			10832832700931865768319939320548036799950876081126688079535066133906784379562,
			9032441146586796702012724845856317465299885120859242382077037837627029696141
		);

		vk.IC[33] = Pairing.G1Point(
			7420412349928460424224271501279427587593184527274247631661643404636290694605,
			8755422471860050901282671888724467836819037886030296119243594912440714964682
		);

		vk.IC[34] = Pairing.G1Point(
			21569503585394963453826230750080951990529479102265079599755899322888881100183,
			21087999959798467502651314027194564802514325116126249964252540211016684992085
		);
	}

	function verifySignature(uint256[] memory input, SignatureProof memory proof) internal view returns (uint256) {
		uint256 snark_scalar_field = 21888242871839275222246405745257275088548364400416034343698204186575808495617;
		SignatureVerifyingKey memory vk = signatureVerifyingKey();
		require(input.length + 1 == vk.IC.length, "verifier-bad-input");
		// Compute the linear combination vk_x
		Pairing.G1Point memory vk_x = Pairing.G1Point(0, 0);
		for (uint256 i = 0; i < input.length; i++) {
			require(input[i] < snark_scalar_field, "verifier-gte-snark-scalar-field");
			vk_x = Pairing.addition(vk_x, Pairing.scalar_mul(vk.IC[i + 1], input[i]));
		}
		vk_x = Pairing.addition(vk_x, vk.IC[0]);
		if (
			!Pairing.pairingProd4(
				Pairing.negate(proof.A),
				proof.B,
				vk.alfa1,
				vk.beta2,
				vk_x,
				vk.gamma2,
				proof.C,
				vk.delta2
			)
		) return 1;
		return 0;
	}

	/// @return r  bool true if proof is valid
	function verifySignatureProof(
		uint256[2] memory a,
		uint256[2][2] memory b,
		uint256[2] memory c,
		uint256[34] memory input
	) public view returns (bool r) {
		SignatureProof memory proof;
		proof.A = Pairing.G1Point(a[0], a[1]);
		proof.B = Pairing.G2Point([b[0][0], b[0][1]], [b[1][0], b[1][1]]);
		proof.C = Pairing.G1Point(c[0], c[1]);
		uint256[] memory inputValues = new uint256[](input.length);
		for (uint256 i = 0; i < input.length; i++) {
			inputValues[i] = input[i];
		}
		if (verifySignature(inputValues, proof) == 0) {
			return true;
		} else {
			return false;
		}
	}
}
