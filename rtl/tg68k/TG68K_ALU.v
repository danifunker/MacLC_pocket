module TG68K_ALU
  (input  clk,
   input  Reset,
   input  clkena_lw,
   input  [1:0] CPU,
   input  execOPC,
   input  decodeOPC,
   input  exe_condition,
   input  exec_tas,
   input  long_start,
   input  non_aligned,
   input  check_aligned,
   input  movem_presub,
   input  set_stop,
   input  Z_error,
   input  [1:0] rot_bits,
   input  [88:0] exec,
   input  [31:0] OP1out,
   input  [31:0] OP2out,
   input  [31:0] reg_QA,
   input  [31:0] reg_QB,
   input  [15:0] opcode,
   input  [15:0] exe_opcode,
   input  [1:0] exe_datatype,
   input  [15:0] sndOPC,
   input  [15:0] last_data_read,
   input  [15:0] data_read,
   input  [7:0] FlagsSR,
   input  [6:0] micro_state,
   input  [7:0] bf_ext_in,
   input  [5:0] bf_shift,
   input  [5:0] bf_width,
   input  [31:0] bf_ffo_offset,
   input  [4:0] bf_loffset,
   output [7:0] bf_ext_out,
   output set_V_Flag,
   output [7:0] Flags,
   output [2:0] c_out,
   output [31:0] addsub_q,
   output [31:0] ALUout);
  wire [31:0] op1in;
  wire [31:0] addsub_a;
  wire [31:0] addsub_b;
  wire [33:0] notaddsub_b;
  wire [33:0] add_result;
  wire [2:0] addsub_ofl;
  wire opaddsub;
  wire [3:0] c_in;
  wire [2:0] flag_z;
  wire [3:0] set_flags;
  wire [7:0] ccrin;
  wire [3:0] last_flags1;
  wire [9:0] bcd_pur;
  wire [8:0] bcd_kor;
  wire halve_carry;
  wire vflag_a;
  wire bcd_a_carry;
  wire [8:0] bcd_a;
  wire [127:0] result_mulu;
  wire [63:0] result_div;
  wire [31:0] result_div_pre;
  wire v_flag;
  wire rot_rot;
  wire rot_x;
  wire rot_c;
  wire [31:0] rot_out;
  wire asl_vflag;
  wire [4:0] bit_number;
  wire [31:0] bits_out;
  wire one_bit_in;
  wire bchg;
  wire bset;
  wire mulu_sign;
  wire muls_msb;
  wire [63:0] mulu_reg;
  wire fasign;
  wire [31:0] faktorb;
  wire [63:0] div_reg;
  wire [63:0] div_quot;
  wire div_neg;
  wire div_bit;
  wire [32:0] div_sub;
  wire [32:0] div_over;
  wire nozero;
  wire div_qsign;
  wire [63:0] dividend;
  wire divs;
  wire signedop;
  wire op1_sign;
  wire [15:0] op2outext;
  wire [31:0] datareg;
  wire [31:0] bf_datareg;
  wire [39:0] result;
  wire [39:0] result_tmp;
  wire [31:0] unshifted_bitmask;
  wire [39:0] inmux0;
  wire [39:0] inmux1;
  wire [39:0] inmux2;
  wire [31:0] inmux3;
  wire [39:0] shifted_bitmask;
  wire [37:0] bitmaskmux0;
  wire [35:0] bitmaskmux1;
  wire [31:0] bitmaskmux2;
  wire [31:0] bitmaskmux3;
  wire [31:0] bf_set2;
  wire [39:0] shift;
  wire [5:0] bf_firstbit;
  wire [3:0] mux;
  wire [4:0] bitnr;
  wire [31:0] mask;
  wire mask_not_zero;
  wire bf_bset;
  wire bf_nflag;
  wire bf_bchg;
  wire bf_ins;
  wire bf_exts;
  wire bf_fffo;
  wire bf_d32;
  wire bf_s32;
  wire [33:0] hot_msb;
  wire [32:0] vector;
  wire [65:0] result_bs;
  wire [5:0] bit_nr;
  wire [5:0] bit_msb;
  wire [5:0] bs_shift;
  wire [5:0] bs_shift_mod;
  wire [32:0] asl_over;
  wire [32:0] asl_over_xor;
  wire [32:0] asr_sign;
  wire msb;
  wire [5:0] ring;
  wire [31:0] alu;
  wire [31:0] bsout;
  wire bs_v;
  wire bs_c;
  wire bs_x;
  wire n8;
  wire n9;
  wire [23:0] n10;
  wire [6:0] n11;
  wire n12;
  wire [31:0] n13;
  wire [31:0] n14;
  wire [31:0] n15;
  wire [31:0] n16;
  wire [31:0] n17;
  wire [31:0] n18;
  wire n19;
  wire n20;
  wire n21;
  wire [7:0] n22;
  wire n23;
  wire n25;
  wire n26;
  wire [31:0] n27;
  wire [31:0] n28;
  wire [31:0] n29;
  wire n30;
  wire n32;
  wire n33;
  wire n35;
  wire [15:0] n36;
  wire [15:0] n37;
  wire [31:0] n38;
  wire n39;
  wire [31:0] n40;
  wire [31:0] n41;
  wire [31:0] n42;
  wire [31:0] n43;
  wire n44;
  wire [31:0] n45;
  wire n46;
  wire [31:0] n47;
  wire n48;
  wire [3:0] n49;
  wire [3:0] n50;
  wire [7:0] n51;
  wire n52;
  wire [31:0] n53;
  wire n54;
  wire n55;
  wire n56;
  wire n57;
  wire [15:0] n58;
  wire [15:0] n59;
  wire [31:0] n60;
  wire n61;
  wire n62;
  wire n63;
  wire n64;
  wire [7:0] n66;
  wire n67;
  wire [3:0] n68;
  wire [3:0] n69;
  wire [7:0] n70;
  wire [7:0] n71;
  wire [7:0] n72;
  wire [15:0] n73;
  wire [7:0] n74;
  wire [7:0] n75;
  wire [7:0] n76;
  wire [7:0] n77;
  wire [7:0] n78;
  wire [15:0] n79;
  wire [15:0] n80;
  wire [15:0] n81;
  wire [15:0] n82;
  wire [15:0] n83;
  wire [15:0] n84;
  wire [31:0] n85;
  wire [31:0] n86;
  wire [31:0] n87;
  wire [31:0] n88;
  wire [31:0] n89;
  wire [31:0] n90;
  wire [31:0] n91;
  wire [7:0] n92;
  wire [7:0] n93;
  wire [23:0] n94;
  wire [23:0] n95;
  wire [23:0] n96;
  wire [31:0] n97;
  wire [31:0] n98;
  wire [31:0] n99;
  wire [31:0] n100;
  wire [31:0] n101;
  wire [7:0] n102;
  wire [7:0] n103;
  wire [23:0] n104;
  wire [23:0] n105;
  wire [23:0] n106;
  wire n111;
  wire n112;
  wire n113;
  wire n114;
  wire [1:0] n115;
  wire n116;
  wire [2:0] n117;
  wire [28:0] n118;
  wire [31:0] n119;
  wire [1:0] n120;
  wire [31:0] n122;
  wire [31:0] n123;
  wire [31:0] n124;
  wire n125;
  wire n128;
  wire n130;
  wire [3:0] n131;
  wire [7:0] n133;
  wire [11:0] n135;
  wire [3:0] n136;
  wire [15:0] n137;
  wire n138;
  wire n139;
  wire n140;
  wire n141;
  wire n142;
  wire n143;
  wire n144;
  wire n145;
  wire n147;
  wire n148;
  wire n149;
  wire n150;
  wire n151;
  wire n152;
  wire n154;
  wire n155;
  wire n156;
  wire n157;
  wire n158;
  wire n159;
  wire n160;
  wire n161;
  wire [31:0] n164;
  wire [31:0] n166;
  wire [31:0] n168;
  wire n169;
  wire n170;
  wire n171;
  wire n172;
  wire n173;
  wire n175;
  wire n176;
  wire [31:0] n177;
  wire n178;
  wire n179;
  wire [15:0] n180;
  wire [15:0] n181;
  wire [15:0] n182;
  wire [15:0] n183;
  wire [15:0] n184;
  wire n186;
  wire n187;
  wire n188;
  wire n189;
  wire n190;
  wire n191;
  wire n192;
  wire [31:0] n194;
  wire [31:0] n195;
  wire n196;
  wire n197;
  wire n199;
  wire [31:0] n202;
  wire [31:0] n203;
  wire [31:0] n204;
  wire [31:0] n205;
  wire [31:0] n206;
  wire [31:0] n207;
  wire n208;
  wire n209;
  wire [32:0] n211;
  wire n212;
  wire [33:0] n213;
  wire [32:0] n215;
  wire n216;
  wire [33:0] n217;
  wire [33:0] n218;
  wire [33:0] n219;
  wire [32:0] n221;
  wire n222;
  wire [33:0] n223;
  wire [33:0] n224;
  wire n225;
  wire n226;
  wire n227;
  wire n228;
  wire n229;
  wire n230;
  wire n231;
  wire n232;
  wire n233;
  wire n234;
  wire n235;
  wire [31:0] n236;
  wire n237;
  wire n238;
  wire n239;
  wire n240;
  wire n241;
  wire n242;
  wire n243;
  wire n244;
  wire n245;
  wire n246;
  wire n247;
  wire n248;
  wire n249;
  wire n250;
  wire n251;
  wire n252;
  wire n253;
  wire n254;
  wire n255;
  wire n256;
  wire n257;
  wire [2:0] n258;
  wire n262;
  wire [8:0] n263;
  wire [9:0] n264;
  wire n265;
  wire n266;
  wire n267;
  wire n268;
  wire n269;
  wire [3:0] n272;
  localparam [8:0] n273 = 9'b000000000;
  wire n275;
  wire [3:0] n277;
  wire [3:0] n278;
  wire n279;
  wire n280;
  wire n281;
  wire n282;
  wire n283;
  wire n284;
  wire [8:0] n285;
  wire [8:0] n286;
  wire n287;
  wire n288;
  wire n289;
  wire n290;
  wire n291;
  wire [3:0] n293;
  wire n294;
  wire n295;
  wire n296;
  wire n297;
  wire n298;
  wire n299;
  wire n300;
  wire n301;
  wire n302;
  wire n303;
  wire n304;
  wire n305;
  wire n306;
  wire [3:0] n308;
  wire n309;
  wire n310;
  wire n311;
  wire n312;
  wire [8:0] n313;
  wire [8:0] n314;
  wire [7:0] n315;
  wire [7:0] n316;
  wire [7:0] n317;
  wire n318;
  wire [8:0] n319;
  wire n320;
  wire n322;
  wire n323;
  wire n324;
  wire n325;
  wire [1:0] n330;
  wire n332;
  wire n334;
  wire [1:0] n335;
  reg n338;
  reg n342;
  wire n348;
  wire n349;
  wire [1:0] n350;
  wire n352;
  wire [4:0] n353;
  wire [2:0] n354;
  wire [4:0] n356;
  wire [4:0] n357;
  wire [1:0] n358;
  wire n360;
  wire [4:0] n361;
  wire [2:0] n362;
  wire [4:0] n364;
  wire [4:0] n365;
  wire [4:0] n366;
  wire n372;
  wire n373;
  wire n374;
  wire [1:0] n380;
  wire n382;
  wire n385;
  wire [2:0] n387;
  wire n389;
  wire n391;
  wire n393;
  wire n395;
  wire n397;
  wire [4:0] n398;
  reg n401;
  reg n405;
  reg n409;
  reg n413;
  reg n417;
  reg n420;
  wire [1:0] n421;
  wire n423;
  wire n426;
  wire [7:0] n428;
  wire [31:0] n445;
  wire [4:0] n446;
  wire n448;
  wire n451;
  wire n452;
  wire n455;
  localparam [31:0] n456 = 32'b00000000000000000000000000000000;
  wire [4:0] n458;
  wire n460;
  wire n463;
  wire n464;
  wire n466;
  wire n467;
  wire [4:0] n469;
  wire n471;
  wire n474;
  wire n475;
  wire n477;
  wire n478;
  wire [4:0] n480;
  wire n482;
  wire n485;
  wire n486;
  wire n488;
  wire n489;
  wire [4:0] n491;
  wire n493;
  wire n496;
  wire n497;
  wire n499;
  wire n500;
  wire [4:0] n502;
  wire n504;
  wire n507;
  wire n508;
  wire n510;
  wire n511;
  wire [4:0] n513;
  wire n515;
  wire n518;
  wire n519;
  wire n521;
  wire n522;
  wire [4:0] n524;
  wire n526;
  wire n529;
  wire n530;
  wire n532;
  wire n533;
  wire [4:0] n535;
  wire n537;
  wire n540;
  wire n541;
  wire n543;
  wire n544;
  wire [4:0] n546;
  wire n548;
  wire n551;
  wire n552;
  wire n554;
  wire n555;
  wire [4:0] n557;
  wire n559;
  wire n562;
  wire n563;
  wire n565;
  wire n566;
  wire [4:0] n568;
  wire n570;
  wire n573;
  wire n574;
  wire n576;
  wire n577;
  wire [4:0] n579;
  wire n581;
  wire n584;
  wire n585;
  wire n587;
  wire n588;
  wire [4:0] n590;
  wire n592;
  wire n595;
  wire n596;
  wire n598;
  wire n599;
  wire [4:0] n601;
  wire n603;
  wire n606;
  wire n607;
  wire n609;
  wire n610;
  wire [4:0] n612;
  wire n614;
  wire n617;
  wire n618;
  wire n620;
  wire n621;
  wire [4:0] n623;
  wire n625;
  wire n628;
  wire n629;
  wire n631;
  wire n632;
  wire [4:0] n634;
  wire n636;
  wire n639;
  wire n640;
  wire n642;
  wire n643;
  wire [4:0] n645;
  wire n647;
  wire n650;
  wire n651;
  wire n653;
  wire n654;
  wire [4:0] n656;
  wire n658;
  wire n661;
  wire n662;
  wire n664;
  wire n665;
  wire [4:0] n667;
  wire n669;
  wire n672;
  wire n673;
  wire n675;
  wire n676;
  wire [4:0] n678;
  wire n680;
  wire n683;
  wire n684;
  wire n686;
  wire n687;
  wire [4:0] n689;
  wire n691;
  wire n694;
  wire n695;
  wire n697;
  wire n698;
  wire [4:0] n700;
  wire n702;
  wire n705;
  wire n706;
  wire n708;
  wire n709;
  wire [4:0] n711;
  wire n713;
  wire n716;
  wire n717;
  wire n719;
  wire n720;
  wire [4:0] n722;
  wire n724;
  wire n727;
  wire n728;
  wire n730;
  wire n731;
  wire [4:0] n733;
  wire n735;
  wire n738;
  wire n739;
  wire n741;
  wire n742;
  wire [4:0] n744;
  wire n746;
  wire n749;
  wire n750;
  wire n752;
  wire n753;
  wire [4:0] n755;
  wire n757;
  wire n760;
  wire n761;
  wire n763;
  wire n764;
  wire [4:0] n766;
  wire n768;
  wire n771;
  wire n772;
  wire n774;
  wire n775;
  wire [4:0] n777;
  wire n779;
  wire n782;
  wire n783;
  wire n784;
  wire n785;
  wire n786;
  wire n787;
  wire [4:0] n788;
  wire n790;
  wire n793;
  wire n794;
  wire [4:0] n796;
  wire n799;
  wire [31:0] n800;
  wire [31:0] n801;
  wire n802;
  wire [15:0] n803;
  wire [15:0] n804;
  wire [31:0] n805;
  wire [31:0] n806;
  wire n807;
  wire [23:0] n808;
  wire [7:0] n809;
  wire [31:0] n810;
  wire [31:0] n811;
  wire n812;
  wire [35:0] n814;
  wire [3:0] n815;
  wire [3:0] n816;
  wire [3:0] n817;
  wire [31:0] n818;
  wire [35:0] n820;
  wire [35:0] n821;
  wire [35:0] n822;
  wire n823;
  wire [37:0] n825;
  wire [1:0] n826;
  wire [1:0] n827;
  wire [1:0] n828;
  wire [35:0] n829;
  wire [37:0] n831;
  wire [37:0] n832;
  wire [37:0] n833;
  wire n834;
  wire [38:0] n836;
  wire [39:0] n838;
  wire n839;
  wire n840;
  wire n841;
  wire [38:0] n842;
  wire [39:0] n844;
  wire [39:0] n845;
  wire [39:0] n846;
  wire [39:0] n847;
  wire [7:0] n848;
  wire [7:0] n849;
  wire [7:0] n850;
  wire [31:0] n851;
  wire n852;
  wire n853;
  wire [38:0] n854;
  wire [39:0] n855;
  wire [39:0] n856;
  wire n857;
  wire [1:0] n858;
  wire [37:0] n859;
  wire [39:0] n860;
  wire [39:0] n861;
  wire n862;
  wire [3:0] n863;
  wire [35:0] n864;
  wire [39:0] n865;
  wire [39:0] n866;
  wire n867;
  wire [7:0] n868;
  wire [23:0] n869;
  wire [31:0] n870;
  wire [31:0] n871;
  wire [31:0] n872;
  wire n873;
  wire [15:0] n874;
  wire [15:0] n875;
  wire [31:0] n876;
  wire [31:0] n877;
  wire [7:0] n878;
  wire [31:0] n879;
  wire [7:0] n880;
  wire [39:0] n881;
  wire [39:0] n883;
  wire [39:0] n884;
  wire [39:0] n885;
  wire [39:0] n887;
  wire [39:0] n888;
  wire [39:0] n889;
  wire [39:0] n890;
  wire n891;
  wire n892;
  wire n893;
  wire n894;
  wire n896;
  wire n897;
  wire n898;
  wire n899;
  wire n901;
  wire n902;
  wire n903;
  wire n904;
  wire n906;
  wire n907;
  wire n908;
  wire n909;
  wire n911;
  wire n912;
  wire n913;
  wire n914;
  wire n916;
  wire n917;
  wire n918;
  wire n919;
  wire n921;
  wire n922;
  wire n923;
  wire n924;
  wire n926;
  wire n927;
  wire n928;
  wire n929;
  wire n931;
  wire n932;
  wire n933;
  wire n934;
  wire n936;
  wire n937;
  wire n938;
  wire n939;
  wire n941;
  wire n942;
  wire n943;
  wire n944;
  wire n946;
  wire n947;
  wire n948;
  wire n949;
  wire n951;
  wire n952;
  wire n953;
  wire n954;
  wire n956;
  wire n957;
  wire n958;
  wire n959;
  wire n961;
  wire n962;
  wire n963;
  wire n964;
  wire n966;
  wire n967;
  wire n968;
  wire n969;
  wire n971;
  wire n972;
  wire n973;
  wire n974;
  wire n976;
  wire n977;
  wire n978;
  wire n979;
  wire n981;
  wire n982;
  wire n983;
  wire n984;
  wire n986;
  wire n987;
  wire n988;
  wire n989;
  wire n991;
  wire n992;
  wire n993;
  wire n994;
  wire n996;
  wire n997;
  wire n998;
  wire n999;
  wire n1001;
  wire n1002;
  wire n1003;
  wire n1004;
  wire n1006;
  wire n1007;
  wire n1008;
  wire n1009;
  wire n1011;
  wire n1012;
  wire n1013;
  wire n1014;
  wire n1016;
  wire n1017;
  wire n1018;
  wire n1019;
  wire n1021;
  wire n1022;
  wire n1023;
  wire n1024;
  wire n1026;
  wire n1027;
  wire n1028;
  wire n1029;
  wire n1031;
  wire n1032;
  wire n1033;
  wire n1034;
  wire n1036;
  wire n1037;
  wire n1038;
  wire n1039;
  wire n1041;
  wire n1042;
  wire n1043;
  wire n1044;
  wire n1046;
  wire n1047;
  wire n1048;
  wire n1049;
  wire n1051;
  wire n1052;
  wire n1053;
  wire n1054;
  wire n1056;
  wire n1057;
  wire n1058;
  wire n1059;
  wire n1061;
  wire n1062;
  wire n1063;
  wire n1064;
  wire n1066;
  wire n1067;
  wire n1068;
  wire n1069;
  wire n1071;
  wire n1072;
  wire n1073;
  wire n1074;
  wire n1076;
  wire n1077;
  wire n1078;
  wire n1079;
  wire n1081;
  wire n1082;
  wire n1083;
  wire n1084;
  wire n1085;
  wire n1086;
  wire n1087;
  wire n1088;
  wire [5:0] n1090;
  wire [5:0] n1091;
  wire [5:0] n1092;
  wire [3:0] n1093;
  wire n1095;
  wire [3:0] n1096;
  wire n1098;
  wire [3:0] n1099;
  wire n1101;
  wire [3:0] n1102;
  wire n1104;
  wire [3:0] n1106;
  wire n1108;
  wire [3:0] n1109;
  wire n1111;
  wire [3:0] n1113;
  wire n1115;
  wire [3:0] n1117;
  wire [3:0] n1118;
  wire [3:0] n1119;
  wire n1121;
  wire [3:0] n1122;
  wire [3:0] n1124;
  wire [1:0] n1125;
  wire n1126;
  wire n1127;
  wire n1128;
  wire n1130;
  wire [3:0] n1131;
  wire [3:0] n1132;
  wire [1:0] n1133;
  wire [1:0] n1135;
  wire [3:0] n1136;
  wire [3:0] n1139;
  wire [1:0] n1140;
  wire [2:0] n1141;
  wire [1:0] n1142;
  wire [1:0] n1143;
  wire n1144;
  wire n1146;
  wire [3:0] n1147;
  wire [3:0] n1149;
  wire [2:0] n1150;
  wire n1151;
  wire n1153;
  wire n1154;
  wire n1155;
  wire n1156;
  wire n1158;
  wire [3:0] n1159;
  wire [3:0] n1161;
  wire [2:0] n1162;
  wire n1163;
  wire n1164;
  wire [1:0] n1165;
  wire [1:0] n1167;
  wire [3:0] n1168;
  wire [3:0] n1169;
  wire [2:0] n1170;
  wire [2:0] n1172;
  localparam [4:0] n1173 = 5'b11111;
  wire [1:0] n1175;
  wire n1177;
  wire n1179;
  wire n1180;
  wire n1182;
  wire n1183;
  wire n1186;
  wire n1187;
  wire n1188;
  wire n1190;
  wire n1191;
  wire n1192;
  wire n1194;
  wire n1195;
  wire [1:0] n1196;
  wire n1197;
  wire n1198;
  wire n1199;
  wire n1200;
  wire n1201;
  wire n1204;
  wire [1:0] n1209;
  wire n1210;
  wire n1212;
  wire n1213;
  wire n1215;
  wire n1217;
  wire n1218;
  wire n1219;
  wire n1221;
  wire [2:0] n1222;
  reg n1223;
  wire n1241;
  wire n1242;
  wire n1244;
  wire n1245;
  wire n1247;
  wire n1248;
  wire n1251;
  wire n1252;
  wire n1272;
  wire n1273;
  wire n1276;
  wire n1277;
  wire [31:0] n1278;
  wire n1283;
  wire [1:0] n1284;
  wire n1286;
  wire n1288;
  wire n1290;
  wire n1291;
  wire n1293;
  wire [2:0] n1294;
  reg [5:0] n1299;
  wire [1:0] n1300;
  wire n1302;
  wire n1304;
  wire n1306;
  wire n1307;
  wire n1309;
  wire [2:0] n1310;
  reg [5:0] n1315;
  wire [5:0] n1316;
  wire [1:0] n1318;
  wire n1320;
  wire n1321;
  wire n1322;
  wire n1323;
  wire n1324;
  wire [5:0] n1325;
  wire [2:0] n1326;
  wire [2:0] n1327;
  wire n1329;
  wire [2:0] n1332;
  wire [5:0] n1333;
  wire [5:0] n1334;
  wire [5:0] n1336;
  localparam [33:0] n1339 = 34'b0000000000000000000000000000000000;
  wire n1343;
  wire [5:0] n1344;
  wire [5:0] n1346;
  wire [30:0] n1348;
  wire [31:0] n1350;
  wire [30:0] n1351;
  wire [31:0] n1353;
  wire [31:0] n1354;
  wire [32:0] n1355;
  wire [1:0] n1356;
  wire n1359;
  wire n1362;
  wire n1364;
  wire n1365;
  wire [1:0] n1366;
  wire n1367;
  reg n1368;
  wire n1369;
  reg n1370;
  wire [7:0] n1372;
  wire [15:0] n1373;
  wire [6:0] n1374;
  wire [31:0] n1375;
  wire [32:0] n1377;
  wire [32:0] n1378;
  wire n1380;
  wire n1381;
  wire n1382;
  wire n1383;
  wire n1384;
  wire n1386;
  wire n1388;
  wire n1389;
  wire n1390;
  wire [1:0] n1391;
  wire n1392;
  wire n1394;
  wire n1395;
  wire n1397;
  wire n1399;
  wire n1400;
  wire n1401;
  wire n1403;
  wire [2:0] n1404;
  reg n1405;
  wire n1406;
  wire n1408;
  wire n1409;
  wire [1:0] n1410;
  wire [7:0] n1411;
  wire [7:0] n1412;
  wire [7:0] n1413;
  wire n1414;
  wire n1416;
  wire [15:0] n1417;
  wire [15:0] n1418;
  wire [15:0] n1419;
  wire n1420;
  wire n1422;
  wire n1424;
  wire n1425;
  wire [31:0] n1426;
  wire [31:0] n1427;
  wire [31:0] n1428;
  wire n1429;
  wire n1431;
  wire [2:0] n1432;
  wire [7:0] n1433;
  wire [7:0] n1434;
  reg [7:0] n1436;
  wire [7:0] n1437;
  wire [7:0] n1438;
  reg [7:0] n1440;
  wire [15:0] n1441;
  reg [15:0] n1443;
  reg n1444;
  wire n1445;
  wire n1446;
  wire n1447;
  wire n1449;
  wire [1:0] n1450;
  wire [7:0] n1451;
  wire [7:0] n1452;
  wire [7:0] n1453;
  wire n1454;
  wire n1455;
  wire n1456;
  wire n1458;
  wire [15:0] n1459;
  wire [15:0] n1460;
  wire [15:0] n1461;
  wire n1462;
  wire n1463;
  wire n1464;
  wire n1466;
  wire n1468;
  wire n1469;
  wire [31:0] n1470;
  wire [31:0] n1471;
  wire [31:0] n1472;
  wire n1473;
  wire n1474;
  wire n1475;
  wire n1477;
  wire [2:0] n1478;
  wire [7:0] n1479;
  wire [7:0] n1480;
  reg [7:0] n1482;
  wire [7:0] n1483;
  wire [7:0] n1484;
  reg [7:0] n1486;
  wire [15:0] n1487;
  reg [15:0] n1489;
  reg n1490;
  wire n1491;
  wire n1492;
  wire [31:0] n1493;
  wire [31:0] n1494;
  wire [31:0] n1495;
  wire [31:0] n1496;
  wire [31:0] n1497;
  wire n1498;
  wire [31:0] n1499;
  wire [31:0] n1500;
  wire n1502;
  wire n1503;
  wire n1505;
  wire n1507;
  wire n1508;
  wire n1510;
  wire n1511;
  wire n1513;
  wire n1514;
  wire n1515;
  wire n1517;
  wire n1519;
  wire [5:0] n1521;
  wire n1523;
  wire [5:0] n1525;
  wire n1527;
  wire [5:0] n1529;
  wire n1531;
  wire [5:0] n1533;
  wire n1535;
  wire [5:0] n1537;
  wire n1539;
  wire [5:0] n1541;
  wire [5:0] n1542;
  wire [5:0] n1543;
  wire [5:0] n1544;
  wire [5:0] n1545;
  wire [5:0] n1546;
  wire [5:0] n1547;
  wire [5:0] n1549;
  wire n1551;
  wire n1553;
  wire [5:0] n1555;
  wire n1557;
  wire [5:0] n1559;
  wire n1561;
  wire [5:0] n1563;
  wire [5:0] n1564;
  wire [5:0] n1565;
  wire [5:0] n1566;
  wire n1568;
  wire n1570;
  wire [5:0] n1572;
  wire [5:0] n1573;
  wire n1575;
  wire [2:0] n1576;
  wire [5:0] n1578;
  wire n1580;
  wire [3:0] n1581;
  wire [5:0] n1583;
  wire n1585;
  wire [4:0] n1586;
  wire [5:0] n1588;
  wire n1590;
  wire [5:0] n1591;
  reg [5:0] n1593;
  wire n1594;
  wire n1595;
  wire [5:0] n1596;
  wire [5:0] n1597;
  wire n1598;
  wire n1599;
  wire n1600;
  wire n1601;
  wire [5:0] n1603;
  wire [5:0] n1604;
  wire n1605;
  wire n1606;
  wire n1607;
  wire [5:0] n1609;
  wire [5:0] n1610;
  wire [5:0] n1611;
  wire n1612;
  wire n1613;
  wire n1614;
  wire [5:0] n1616;
  wire [5:0] n1618;
  wire n1620;
  wire [5:0] n1621;
  wire n1622;
  wire [5:0] n1623;
  wire n1624;
  wire [31:0] n1625;
  wire [31:0] n1626;
  wire [31:0] n1627;
  localparam [32:0] n1628 = 33'b000000000000000000000000000000000;
  wire n1629;
  wire n1631;
  wire n1632;
  wire n1633;
  wire n1634;
  wire n1635;
  wire [31:0] n1636;
  wire [31:0] n1637;
  wire n1638;
  wire n1640;
  wire [31:0] n1641;
  wire n1642;
  wire [32:0] n1644;
  wire [1:0] n1645;
  wire n1646;
  localparam [23:0] n1647 = 24'b000000000000000000000000;
  localparam [23:0] n1648 = 24'b000000000000000000000000;
  wire n1650;
  wire n1651;
  wire n1652;
  wire n1653;
  wire [22:0] n1654;
  wire n1656;
  wire n1657;
  localparam [15:0] n1658 = 16'b0000000000000000;
  wire n1661;
  wire n1662;
  wire n1663;
  wire n1664;
  wire [14:0] n1665;
  wire n1667;
  wire n1669;
  wire n1670;
  wire n1671;
  wire n1673;
  wire n1674;
  wire n1675;
  wire n1676;
  wire n1678;
  wire [2:0] n1679;
  wire n1680;
  reg n1681;
  wire [6:0] n1682;
  wire [6:0] n1683;
  reg [6:0] n1684;
  wire n1685;
  wire n1686;
  reg n1687;
  wire [14:0] n1688;
  wire [14:0] n1689;
  reg [14:0] n1690;
  wire n1691;
  reg n1692;
  wire [7:0] n1694;
  reg n1698;
  wire [7:0] n1699;
  wire [7:0] n1700;
  reg [7:0] n1701;
  wire [15:0] n1702;
  wire [15:0] n1703;
  reg [15:0] n1704;
  wire [7:0] n1706;
  wire [65:0] n1708;
  wire [30:0] n1709;
  wire [31:0] n1710;
  wire [65:0] n1711;
  wire n1715;
  wire [7:0] n1716;
  wire [7:0] n1717;
  wire n1718;
  wire [7:0] n1719;
  wire [7:0] n1720;
  wire n1721;
  wire [7:0] n1722;
  wire [7:0] n1723;
  wire [7:0] n1724;
  wire [7:0] n1725;
  wire [7:0] n1726;
  wire [7:0] n1727;
  wire n1728;
  wire n1729;
  wire n1730;
  wire n1731;
  wire [7:0] n1732;
  wire n1734;
  wire [7:0] n1736;
  wire n1738;
  wire [15:0] n1740;
  wire n1742;
  wire n1745;
  wire [1:0] n1746;
  wire [1:0] n1748;
  wire [2:0] n1749;
  wire [2:0] n1751;
  wire [2:0] n1753;
  wire n1756;
  wire n1757;
  wire n1758;
  wire [1:0] n1759;
  wire n1760;
  wire [2:0] n1761;
  wire n1762;
  wire [3:0] n1763;
  wire n1764;
  wire n1765;
  wire n1766;
  wire [1:0] n1767;
  wire [1:0] n1768;
  wire [1:0] n1769;
  wire [1:0] n1770;
  wire n1772;
  wire n1773;
  wire n1774;
  wire n1775;
  wire n1776;
  wire [1:0] n1777;
  wire n1778;
  wire [2:0] n1779;
  wire n1780;
  wire [3:0] n1781;
  wire n1782;
  wire n1783;
  wire [1:0] n1784;
  wire n1785;
  wire [2:0] n1786;
  wire n1787;
  wire [3:0] n1788;
  wire [3:0] n1789;
  wire [3:0] n1790;
  wire [3:0] n1791;
  wire n1793;
  wire n1794;
  wire [7:0] n1795;
  wire [7:0] n1796;
  wire n1797;
  wire [7:0] n1798;
  wire [7:0] n1799;
  wire n1800;
  wire n1801;
  wire n1802;
  wire n1803;
  wire n1804;
  wire n1805;
  wire n1807;
  wire n1808;
  wire n1810;
  wire n1811;
  wire n1812;
  wire n1813;
  wire n1814;
  wire [1:0] n1816;
  wire [3:0] n1818;
  wire [3:0] n1820;
  wire [3:0] n1821;
  wire [3:0] n1822;
  wire n1823;
  wire n1824;
  wire [3:0] n1825;
  wire n1826;
  wire n1827;
  wire n1828;
  wire n1830;
  wire n1831;
  wire n1832;
  wire n1833;
  wire n1834;
  wire n1835;
  wire n1836;
  wire n1837;
  wire n1838;
  wire n1839;
  wire n1840;
  wire n1841;
  wire n1842;
  wire n1843;
  wire n1845;
  wire n1847;
  wire n1849;
  wire n1850;
  wire n1851;
  wire [1:0] n1852;
  wire [3:0] n1854;
  wire n1855;
  wire n1856;
  wire [1:0] n1857;
  wire [3:0] n1859;
  wire [3:0] n1860;
  wire [3:0] n1861;
  wire n1862;
  wire n1864;
  wire n1865;
  wire n1866;
  wire n1867;
  wire n1868;
  wire n1872;
  wire n1873;
  wire n1874;
  wire n1875;
  wire n1876;
  wire n1877;
  wire n1878;
  wire n1879;
  wire n1880;
  wire n1881;
  wire n1882;
  wire n1883;
  wire n1884;
  wire n1885;
  wire n1887;
  wire n1888;
  wire n1891;
  wire n1892;
  wire n1893;
  wire n1894;
  wire n1895;
  wire [1:0] n1896;
  wire n1898;
  wire n1899;
  wire n1900;
  wire n1901;
  wire n1902;
  wire n1905;
  wire n1906;
  wire [1:0] n1907;
  wire n1908;
  wire n1909;
  wire n1910;
  wire n1911;
  wire n1912;
  wire n1913;
  wire n1914;
  wire n1915;
  wire n1916;
  wire n1917;
  wire n1918;
  wire n1919;
  wire n1920;
  wire n1921;
  wire n1922;
  wire n1923;
  wire n1924;
  wire n1925;
  wire n1926;
  wire n1927;
  wire n1928;
  wire n1929;
  wire n1931;
  wire n1932;
  wire n1933;
  wire n1934;
  wire n1935;
  wire n1936;
  wire n1938;
  wire n1939;
  wire n1940;
  wire n1941;
  wire [15:0] n1942;
  wire n1944;
  wire n1946;
  wire [15:0] n1947;
  wire n1949;
  wire n1950;
  wire n1951;
  wire n1954;
  wire [3:0] n1957;
  wire [3:0] n1958;
  wire [3:0] n1959;
  wire [3:0] n1960;
  wire [3:0] n1961;
  wire [1:0] n1962;
  wire [1:0] n1963;
  wire [1:0] n1964;
  wire n1965;
  wire n1966;
  wire n1967;
  wire n1968;
  wire n1969;
  wire [3:0] n1970;
  wire [3:0] n1971;
  wire [3:0] n1972;
  wire [3:0] n1973;
  wire [3:0] n1974;
  wire [3:0] n1975;
  wire [3:0] n1976;
  wire [3:0] n1977;
  wire [3:0] n1978;
  wire [3:0] n1979;
  wire [3:0] n1980;
  wire [4:0] n1981;
  wire [4:0] n1982;
  wire [4:0] n1983;
  wire [3:0] n1984;
  wire [3:0] n1985;
  wire [3:0] n1986;
  wire n1987;
  wire n1988;
  wire n1989;
  wire [3:0] n1990;
  wire [4:0] n1991;
  wire [4:0] n1992;
  wire [4:0] n1993;
  wire [2:0] n1994;
  wire [2:0] n1995;
  wire [2:0] n1996;
  wire [3:0] n1998;
  wire [7:0] n1999;
  wire [7:0] n2000;
  wire [3:0] n2001;
  wire n2002;
  wire [7:0] n2004;
  wire [3:0] n2005;
  wire n2006;
  wire [4:0] n2008;
  wire [7:0] n2009;
  wire n2016;
  wire n2017;
  wire n2018;
  wire n2019;
  wire n2021;
  wire n2022;
  wire n2023;
  wire n2026;
  wire [62:0] n2027;
  wire [63:0] n2028;
  wire n2029;
  wire [31:0] n2030;
  wire [32:0] n2031;
  wire [32:0] n2032;
  wire [32:0] n2033;
  wire [31:0] n2034;
  wire [32:0] n2035;
  wire [32:0] n2036;
  wire [32:0] n2037;
  wire [32:0] n2038;
  wire [32:0] n2039;
  wire [32:0] n2040;
  wire [30:0] n2041;
  wire n2042;
  wire n2044;
  wire [15:0] n2045;
  wire [31:0] n2047;
  wire [31:0] n2048;
  wire [31:0] n2071;
  wire n2079;
  wire n2080;
  wire n2081;
  wire n2082;
  wire n2083;
  wire n2084;
  wire n2085;
  wire n2086;
  wire n2088;
  wire n2089;
  wire n2090;
  wire n2091;
  wire n2092;
  wire n2093;
  wire n2094;
  wire n2095;
  wire n2096;
  wire n2097;
  wire n2098;
  wire n2099;
  wire n2100;
  wire n2101;
  wire n2102;
  wire n2103;
  wire n2104;
  wire n2105;
  wire n2106;
  wire n2107;
  wire n2108;
  wire n2109;
  wire n2110;
  wire n2111;
  wire n2112;
  wire n2113;
  wire n2114;
  wire n2115;
  wire n2116;
  wire n2117;
  wire n2118;
  wire n2119;
  wire n2120;
  wire n2121;
  wire n2122;
  wire n2123;
  wire n2124;
  wire n2125;
  wire n2126;
  wire n2127;
  wire n2128;
  wire n2129;
  wire n2130;
  wire n2131;
  wire n2132;
  wire n2133;
  wire n2134;
  wire n2135;
  wire n2136;
  wire n2137;
  wire n2138;
  wire n2139;
  wire n2140;
  wire n2141;
  wire n2142;
  wire n2143;
  wire n2144;
  wire n2145;
  wire n2146;
  wire n2147;
  wire n2148;
  wire n2149;
  wire n2150;
  wire n2151;
  wire [3:0] n2152;
  wire [3:0] n2153;
  wire [3:0] n2154;
  wire [3:0] n2155;
  wire [3:0] n2156;
  wire [3:0] n2157;
  wire [3:0] n2158;
  wire [3:0] n2159;
  wire [15:0] n2160;
  wire [15:0] n2161;
  wire [31:0] n2162;
  wire n2163;
  wire n2165;
  wire n2166;
  wire n2167;
  wire n2168;
  wire n2169;
  wire [31:0] n2170;
  wire n2171;
  wire n2172;
  wire [63:0] n2173;
  wire [15:0] n2174;
  wire [15:0] n2175;
  wire [31:0] n2176;
  wire [31:0] n2177;
  wire [15:0] n2178;
  wire [15:0] n2179;
  wire [15:0] n2180;
  wire n2182;
  wire n2183;
  wire n2184;
  wire [15:0] n2185;
  wire [15:0] n2187;
  wire n2188;
  wire n2189;
  wire [32:0] n2190;
  wire [32:0] n2192;
  wire [32:0] n2193;
  wire [32:0] n2194;
  wire [16:0] n2196;
  wire [15:0] n2197;
  wire [32:0] n2198;
  wire [32:0] n2199;
  wire [32:0] n2200;
  wire n2201;
  wire [31:0] n2202;
  wire [31:0] n2203;
  wire [31:0] n2204;
  wire [30:0] n2205;
  wire n2206;
  wire [31:0] n2207;
  wire [31:0] n2208;
  wire [31:0] n2210;
  wire [31:0] n2211;
  wire [31:0] n2212;
  wire n2213;
  wire n2214;
  wire n2215;
  wire n2216;
  wire n2217;
  wire n2218;
  wire n2219;
  wire n2220;
  wire n2221;
  wire n2222;
  wire n2223;
  wire n2224;
  wire n2226;
  wire n2229;
  wire n2235;
  wire n2238;
  wire n2239;
  wire n2240;
  wire [63:0] n2242;
  wire [63:0] n2243;
  wire n2246;
  wire n2247;
  wire n2248;
  wire [63:0] n2249;
  wire n2251;
  wire n2254;
  wire n2255;
  wire n2256;
  wire n2257;
  wire [31:0] n2258;
  wire [32:0] n2260;
  wire [16:0] n2262;
  wire [15:0] n2263;
  wire [32:0] n2264;
  wire [32:0] n2265;
  wire n2268;
  wire n2269;
  wire [31:0] n2270;
  wire [31:0] n2272;
  wire [31:0] n2273;
  wire [31:0] n2274;
  wire [63:0] n2275;
  wire n2277;
  wire n2278;
  wire n2280;
  wire n2281;
  wire n2284;
  wire [31:0] n2294;
  wire [2:0] n2295;
  wire [3:0] n2296;
  reg [3:0] n2297;
  wire [8:0] n2298;
  wire [127:0] n2300;
  wire [63:0] n2301;
  reg [63:0] n2302;
  wire n2303;
  reg n2304;
  reg n2305;
  wire n2307;
  reg n2308;
  wire n2309;
  reg n2310;
  wire [31:0] n2312;
  wire [31:0] n2313;
  reg [31:0] n2314;
  wire [63:0] n2316;
  wire [63:0] n2319;
  reg [63:0] n2320;
  wire [63:0] n2321;
  wire n2323;
  reg n2324;
  wire [32:0] n2325;
  reg [32:0] n2326;
  wire n2327;
  reg n2328;
  wire [63:0] n2329;
  wire n2330;
  reg n2331;
  wire n2332;
  reg n2333;
  wire [31:0] n2336;
  wire [39:0] n2338;
  wire [31:0] n2339;
  wire [39:0] n2341;
  wire [4:0] n2342;
  wire n2343;
  reg n2344;
  wire n2345;
  reg n2346;
  wire n2347;
  reg n2348;
  wire n2349;
  reg n2350;
  wire n2351;
  reg n2352;
  wire n2353;
  reg n2354;
  wire n2355;
  reg n2356;
  wire [32:0] n2358;
  wire [32:0] n2359;
  wire [32:0] n2360;
  wire [31:0] n2361;
  wire [7:0] n2362;
  reg [7:0] n2363;
  reg [7:0] n2364;
  wire n2365;
  wire n2366;
  wire n2367;
  wire n2368;
  wire n2369;
  wire n2370;
  wire n2371;
  wire n2372;
  wire n2373;
  wire n2374;
  wire n2375;
  wire n2376;
  wire n2377;
  wire n2378;
  wire n2379;
  wire n2380;
  wire n2381;
  wire n2382;
  wire n2383;
  wire n2384;
  wire n2385;
  wire n2386;
  wire n2387;
  wire n2388;
  wire n2389;
  wire n2390;
  wire n2391;
  wire n2392;
  wire n2393;
  wire n2394;
  wire n2395;
  wire n2396;
  wire n2397;
  wire n2398;
  wire n2399;
  wire n2400;
  wire n2401;
  wire n2402;
  wire n2403;
  wire n2404;
  wire n2405;
  wire n2406;
  wire n2407;
  wire n2408;
  wire n2409;
  wire n2410;
  wire n2411;
  wire n2412;
  wire n2413;
  wire n2414;
  wire n2415;
  wire n2416;
  wire n2417;
  wire n2418;
  wire n2419;
  wire n2420;
  wire n2421;
  wire n2422;
  wire n2423;
  wire n2424;
  wire n2425;
  wire n2426;
  wire n2427;
  wire n2428;
  wire n2429;
  wire n2430;
  wire n2431;
  wire n2432;
  wire n2433;
  wire n2434;
  wire n2435;
  wire n2436;
  wire n2437;
  wire n2438;
  wire n2439;
  wire n2440;
  wire n2441;
  wire n2442;
  wire n2443;
  wire n2444;
  wire n2445;
  wire n2446;
  wire n2447;
  wire n2448;
  wire n2449;
  wire n2450;
  wire n2451;
  wire n2452;
  wire n2453;
  wire n2454;
  wire n2455;
  wire n2456;
  wire n2457;
  wire n2458;
  wire n2459;
  wire n2460;
  wire n2461;
  wire n2462;
  wire n2463;
  wire n2464;
  wire n2465;
  wire n2466;
  wire n2467;
  wire n2468;
  wire n2469;
  wire n2470;
  wire n2471;
  wire n2472;
  wire n2473;
  wire n2474;
  wire n2475;
  wire n2476;
  wire n2477;
  wire n2478;
  wire n2479;
  wire n2480;
  wire n2481;
  wire n2482;
  wire n2483;
  wire n2484;
  wire n2485;
  wire n2486;
  wire n2487;
  wire n2488;
  wire n2489;
  wire n2490;
  wire n2491;
  wire n2492;
  wire n2493;
  wire n2494;
  wire n2495;
  wire n2496;
  wire n2497;
  wire n2498;
  wire n2499;
  wire [31:0] n2500;
  wire n2501;
  wire n2502;
  wire n2503;
  wire n2504;
  wire n2505;
  wire n2506;
  wire n2507;
  wire n2508;
  wire n2509;
  wire n2510;
  wire n2511;
  wire n2512;
  wire n2513;
  wire n2514;
  wire n2515;
  wire n2516;
  wire n2517;
  wire n2518;
  wire n2519;
  wire n2520;
  wire n2521;
  wire n2522;
  wire n2523;
  wire n2524;
  wire n2525;
  wire n2526;
  wire n2527;
  wire n2528;
  wire n2529;
  wire n2530;
  wire n2531;
  wire n2532;
  wire n2533;
  wire n2534;
  wire n2535;
  wire n2536;
  wire n2537;
  wire n2538;
  wire n2539;
  wire n2540;
  wire n2541;
  wire n2542;
  wire n2543;
  wire n2544;
  wire n2545;
  wire n2546;
  wire n2547;
  wire n2548;
  wire n2549;
  wire n2550;
  wire n2551;
  wire n2552;
  wire n2553;
  wire n2554;
  wire n2555;
  wire n2556;
  wire n2557;
  wire n2558;
  wire n2559;
  wire n2560;
  wire n2561;
  wire n2562;
  wire n2563;
  wire n2564;
  wire n2565;
  wire n2566;
  wire n2567;
  wire n2568;
  wire n2569;
  wire n2570;
  wire n2571;
  wire n2572;
  wire n2573;
  wire n2574;
  wire n2575;
  wire n2576;
  wire n2577;
  wire n2578;
  wire n2579;
  wire n2580;
  wire n2581;
  wire n2582;
  wire n2583;
  wire n2584;
  wire n2585;
  wire n2586;
  wire n2587;
  wire n2588;
  wire n2589;
  wire n2590;
  wire n2591;
  wire n2592;
  wire n2593;
  wire n2594;
  wire n2595;
  wire n2596;
  wire n2597;
  wire n2598;
  wire n2599;
  wire n2600;
  wire n2601;
  wire n2602;
  wire n2603;
  wire n2604;
  wire n2605;
  wire n2606;
  wire n2607;
  wire n2608;
  wire n2609;
  wire n2610;
  wire n2611;
  wire n2612;
  wire n2613;
  wire n2614;
  wire n2615;
  wire n2616;
  wire n2617;
  wire n2618;
  wire n2619;
  wire n2620;
  wire n2621;
  wire n2622;
  wire n2623;
  wire n2624;
  wire n2625;
  wire n2626;
  wire n2627;
  wire n2628;
  wire n2629;
  wire n2630;
  wire n2631;
  wire n2632;
  wire n2633;
  wire n2634;
  wire n2635;
  wire n2636;
  wire n2637;
  wire n2638;
  wire n2639;
  wire n2640;
  wire n2641;
  wire n2642;
  wire n2643;
  wire n2644;
  wire n2645;
  wire n2646;
  wire n2647;
  wire n2648;
  wire n2649;
  wire [33:0] n2650;
  assign bf_ext_out = n2363; //(module output)
  assign set_V_Flag = n2229; //(module output)
  assign Flags = n2364; //(module output)
  assign c_out = n258; //(module output)
  assign addsub_q = n236; //(module output)
  assign ALUout = n18; //(module output)
  /* TG68K_ALU.vhd:86:16  */
  assign op1in = n2294; // (signal)
  /* TG68K_ALU.vhd:87:16  */
  assign addsub_a = n124; // (signal)
  /* TG68K_ALU.vhd:88:16  */
  assign addsub_b = n207; // (signal)
  /* TG68K_ALU.vhd:89:16  */
  assign notaddsub_b = n219; // (signal)
  /* TG68K_ALU.vhd:90:16  */
  assign add_result = n224; // (signal)
  /* TG68K_ALU.vhd:91:16  */
  assign addsub_ofl = n2295; // (signal)
  /* TG68K_ALU.vhd:92:16  */
  assign opaddsub = n186; // (signal)
  /* TG68K_ALU.vhd:93:16  */
  assign c_in = n2296; // (signal)
  /* TG68K_ALU.vhd:94:16  */
  assign flag_z = n1753; // (signal)
  /* TG68K_ALU.vhd:95:16  */
  assign set_flags = n1791; // (signal)
  /* TG68K_ALU.vhd:96:16  */
  assign ccrin = n1727; // (signal)
  /* TG68K_ALU.vhd:97:16  */
  assign last_flags1 = n2297; // (signal)
  /* TG68K_ALU.vhd:100:16  */
  assign bcd_pur = n264; // (signal)
  /* TG68K_ALU.vhd:101:16  */
  assign bcd_kor = n2298; // (signal)
  /* TG68K_ALU.vhd:102:16  */
  assign halve_carry = n269; // (signal)
  /* TG68K_ALU.vhd:103:16  */
  assign vflag_a = n322; // (signal)
  /* TG68K_ALU.vhd:104:16  */
  assign bcd_a_carry = n325; // (signal)
  /* TG68K_ALU.vhd:105:16  */
  assign bcd_a = n319; // (signal)
  /* TG68K_ALU.vhd:106:16  */
  assign result_mulu = n2300; // (signal)
  /* TG68K_ALU.vhd:107:16  */
  assign result_div = n2302; // (signal)
  /* TG68K_ALU.vhd:108:16  */
  assign result_div_pre = n2212; // (signal)
  /* TG68K_ALU.vhd:110:16  */
  assign v_flag = n2304; // (signal)
  /* TG68K_ALU.vhd:112:16  */
  assign rot_rot = n1223; // (signal)
  /* TG68K_ALU.vhd:115:16  */
  assign rot_x = n1276; // (signal)
  /* TG68K_ALU.vhd:116:16  */
  assign rot_c = n1277; // (signal)
  /* TG68K_ALU.vhd:117:16  */
  assign rot_out = n1278; // (signal)
  /* TG68K_ALU.vhd:118:16  */
  assign asl_vflag = n2305; // (signal)
  /* TG68K_ALU.vhd:120:16  */
  assign bit_number = n366; // (signal)
  /* TG68K_ALU.vhd:121:16  */
  assign bits_out = n2500; // (signal)
  /* TG68K_ALU.vhd:122:16  */
  assign one_bit_in = n2365; // (signal)
  /* TG68K_ALU.vhd:123:16  */
  assign bchg = n2308; // (signal)
  /* TG68K_ALU.vhd:124:16  */
  assign bset = n2310; // (signal)
  /* TG68K_ALU.vhd:126:16  */
  assign mulu_sign = n2026; // (signal)
  /* TG68K_ALU.vhd:128:16  */
  assign muls_msb = n2021; // (signal)
  /* TG68K_ALU.vhd:129:16  */
  assign mulu_reg = n2316; // (signal)
  /* TG68K_ALU.vhd:130:16  */
  assign fasign = 1'bX; // (signal)
  /* TG68K_ALU.vhd:132:16  */
  assign faktorb = n2048; // (signal)
  /* TG68K_ALU.vhd:134:16  */
  assign div_reg = n2320; // (signal)
  /* TG68K_ALU.vhd:135:16  */
  assign div_quot = n2321; // (signal)
  /* TG68K_ALU.vhd:137:16  */
  assign div_neg = n2324; // (signal)
  /* TG68K_ALU.vhd:138:16  */
  assign div_bit = n2201; // (signal)
  /* TG68K_ALU.vhd:139:16  */
  assign div_sub = n2200; // (signal)
  /* TG68K_ALU.vhd:140:16  */
  assign div_over = n2326; // (signal)
  /* TG68K_ALU.vhd:141:16  */
  assign nozero = n2328; // (signal)
  /* TG68K_ALU.vhd:142:16  */
  assign div_qsign = n2172; // (signal)
  /* TG68K_ALU.vhd:143:16  */
  assign dividend = n2329; // (signal)
  /* TG68K_ALU.vhd:144:16  */
  assign divs = n2086; // (signal)
  /* TG68K_ALU.vhd:145:16  */
  assign signedop = n2331; // (signal)
  /* TG68K_ALU.vhd:146:16  */
  assign op1_sign = n2333; // (signal)
  /* TG68K_ALU.vhd:148:16  */
  assign op2outext = n2187; // (signal)
  /* TG68K_ALU.vhd:151:16  */
  assign datareg = n2336; // (signal)
  /* TG68K_ALU.vhd:153:16  */
  assign bf_datareg = n801; // (signal)
  /* TG68K_ALU.vhd:154:16  */
  assign result = n2338; // (signal)
  /* TG68K_ALU.vhd:155:16  */
  assign result_tmp = n890; // (signal)
  /* TG68K_ALU.vhd:156:16  */
  assign unshifted_bitmask = n2339; // (signal)
  /* TG68K_ALU.vhd:158:16  */
  assign inmux0 = n856; // (signal)
  /* TG68K_ALU.vhd:159:16  */
  assign inmux1 = n861; // (signal)
  /* TG68K_ALU.vhd:160:16  */
  assign inmux2 = n866; // (signal)
  /* TG68K_ALU.vhd:161:16  */
  assign inmux3 = n872; // (signal)
  /* TG68K_ALU.vhd:162:16  */
  assign shifted_bitmask = n846; // (signal)
  /* TG68K_ALU.vhd:163:16  */
  assign bitmaskmux0 = n833; // (signal)
  /* TG68K_ALU.vhd:164:16  */
  assign bitmaskmux1 = n822; // (signal)
  /* TG68K_ALU.vhd:165:16  */
  assign bitmaskmux2 = n811; // (signal)
  /* TG68K_ALU.vhd:166:16  */
  assign bitmaskmux3 = n806; // (signal)
  /* TG68K_ALU.vhd:167:16  */
  assign bf_set2 = n877; // (signal)
  /* TG68K_ALU.vhd:168:16  */
  assign shift = n2341; // (signal)
  /* TG68K_ALU.vhd:169:16  */
  assign bf_firstbit = n1092; // (signal)
  /* TG68K_ALU.vhd:170:16  */
  assign mux = n1169; // (signal)
  /* TG68K_ALU.vhd:171:16  */
  assign bitnr = n2342; // (signal)
  /* TG68K_ALU.vhd:172:16  */
  assign mask = datareg; // (signal)
  /* TG68K_ALU.vhd:173:16  */
  assign mask_not_zero = n1204; // (signal)
  /* TG68K_ALU.vhd:174:16  */
  assign bf_bset = n2344; // (signal)
  /* TG68K_ALU.vhd:175:16  */
  assign bf_nflag = n2501; // (signal)
  /* TG68K_ALU.vhd:176:16  */
  assign bf_bchg = n2346; // (signal)
  /* TG68K_ALU.vhd:177:16  */
  assign bf_ins = n2348; // (signal)
  /* TG68K_ALU.vhd:178:16  */
  assign bf_exts = n2350; // (signal)
  /* TG68K_ALU.vhd:179:16  */
  assign bf_fffo = n2352; // (signal)
  /* TG68K_ALU.vhd:180:16  */
  assign bf_d32 = n2354; // (signal)
  /* TG68K_ALU.vhd:181:16  */
  assign bf_s32 = n2356; // (signal)
  /* TG68K_ALU.vhd:187:16  */
  assign hot_msb = n2650; // (signal)
  /* TG68K_ALU.vhd:188:16  */
  assign vector = n2358; // (signal)
  /* TG68K_ALU.vhd:189:16  */
  assign result_bs = n1711; // (signal)
  /* TG68K_ALU.vhd:190:16  */
  assign bit_nr = n1623; // (signal)
  /* TG68K_ALU.vhd:191:16  */
  assign bit_msb = n1346; // (signal)
  /* TG68K_ALU.vhd:192:16  */
  assign bs_shift = n1336; // (signal)
  /* TG68K_ALU.vhd:193:16  */
  assign bs_shift_mod = n1593; // (signal)
  /* TG68K_ALU.vhd:194:16  */
  assign asl_over = n1378; // (signal)
  /* TG68K_ALU.vhd:195:16  */
  assign asl_over_xor = n2359; // (signal)
  /* TG68K_ALU.vhd:196:16  */
  assign asr_sign = n2360; // (signal)
  /* TG68K_ALU.vhd:197:16  */
  assign msb = n1698; // (signal)
  /* TG68K_ALU.vhd:198:16  */
  assign ring = n1316; // (signal)
  /* TG68K_ALU.vhd:199:16  */
  assign alu = n1500; // (signal)
  /* TG68K_ALU.vhd:200:16  */
  assign bsout = n2361; // (signal)
  /* TG68K_ALU.vhd:201:16  */
  assign bs_v = n1513; // (signal)
  /* TG68K_ALU.vhd:202:16  */
  assign bs_c = n1640; // (signal)
  /* TG68K_ALU.vhd:203:16  */
  assign bs_x = n1515; // (signal)
  /* TG68K_ALU.vhd:215:35  */
  assign n8 = op1in[7]; // extract
  /* TG68K_ALU.vhd:215:39  */
  assign n9 = n8 | exec_tas;
  assign n10 = op1in[31:8]; // extract
  assign n11 = op1in[6:0]; // extract
  /* TG68K_ALU.vhd:216:24  */
  assign n12 = exec[76]; // extract
  /* TG68K_ALU.vhd:217:41  */
  assign n13 = result[31:0]; // extract
  /* TG68K_ALU.vhd:219:57  */
  assign n14 = {26'b0, bf_firstbit};  //  uext
  /* TG68K_ALU.vhd:219:57  */
  assign n15 = bf_ffo_offset - n14;
  /* TG68K_ALU.vhd:218:25  */
  assign n16 = bf_fffo ? n15 : n13;
  assign n17 = {n10, n9, n11};
  /* TG68K_ALU.vhd:216:17  */
  assign n18 = n12 ? n16 : n17;
  /* TG68K_ALU.vhd:224:24  */
  assign n19 = exec[12]; // extract
  /* TG68K_ALU.vhd:224:45  */
  assign n20 = exec[13]; // extract
  /* TG68K_ALU.vhd:224:38  */
  assign n21 = n19 | n20;
  /* TG68K_ALU.vhd:225:51  */
  assign n22 = bcd_a[7:0]; // extract
  /* TG68K_ALU.vhd:226:27  */
  assign n23 = exec[20]; // extract
  /* TG68K_ALU.vhd:226:41  */
  assign n25 = 1'b1 & n23;
  /* TG68K_ALU.vhd:234:40  */
  assign n26 = exec[67]; // extract
  /* TG68K_ALU.vhd:235:61  */
  assign n27 = result_mulu[31:0]; // extract
  /* TG68K_ALU.vhd:238:58  */
  assign n28 = mulu_reg[31:0]; // extract
  /* TG68K_ALU.vhd:234:33  */
  assign n29 = n26 ? n27 : n28;
  /* TG68K_ALU.vhd:241:27  */
  assign n30 = exec[21]; // extract
  /* TG68K_ALU.vhd:241:41  */
  assign n32 = 1'b1 & n30;
  /* TG68K_ALU.vhd:242:38  */
  assign n33 = exe_opcode[15]; // extract
  /* TG68K_ALU.vhd:242:47  */
  assign n35 = n33 | 1'b0;
  /* TG68K_ALU.vhd:244:52  */
  assign n36 = result_div[47:32]; // extract
  /* TG68K_ALU.vhd:244:77  */
  assign n37 = result_div[15:0]; // extract
  /* TG68K_ALU.vhd:244:66  */
  assign n38 = {n36, n37};
  /* TG68K_ALU.vhd:246:40  */
  assign n39 = exec[68]; // extract
  /* TG68K_ALU.vhd:247:60  */
  assign n40 = result_div[63:32]; // extract
  /* TG68K_ALU.vhd:249:60  */
  assign n41 = result_div[31:0]; // extract
  /* TG68K_ALU.vhd:246:33  */
  assign n42 = n39 ? n40 : n41;
  /* TG68K_ALU.vhd:242:25  */
  assign n43 = n35 ? n38 : n42;
  /* TG68K_ALU.vhd:252:27  */
  assign n44 = exec[5]; // extract
  /* TG68K_ALU.vhd:253:41  */
  assign n45 = OP2out | OP1out;
  /* TG68K_ALU.vhd:254:27  */
  assign n46 = exec[6]; // extract
  /* TG68K_ALU.vhd:255:41  */
  assign n47 = OP2out & OP1out;
  /* TG68K_ALU.vhd:256:27  */
  assign n48 = exec[16]; // extract
  assign n49 = {exe_condition, exe_condition, exe_condition, exe_condition};
  assign n50 = {exe_condition, exe_condition, exe_condition, exe_condition};
  assign n51 = {n49, n50};
  /* TG68K_ALU.vhd:258:27  */
  assign n52 = exec[7]; // extract
  /* TG68K_ALU.vhd:259:41  */
  assign n53 = OP2out ^ OP1out;
  /* TG68K_ALU.vhd:261:27  */
  assign n54 = exec[85]; // extract
  /* TG68K_ALU.vhd:264:27  */
  assign n55 = exec[9]; // extract
  /* TG68K_ALU.vhd:266:27  */
  assign n56 = exec[81]; // extract
  /* TG68K_ALU.vhd:268:27  */
  assign n57 = exec[15]; // extract
  /* TG68K_ALU.vhd:269:40  */
  assign n58 = OP1out[15:0]; // extract
  /* TG68K_ALU.vhd:269:61  */
  assign n59 = OP1out[31:16]; // extract
  /* TG68K_ALU.vhd:269:53  */
  assign n60 = {n58, n59};
  /* TG68K_ALU.vhd:270:27  */
  assign n61 = exec[14]; // extract
  /* TG68K_ALU.vhd:272:27  */
  assign n62 = exec[75]; // extract
  /* TG68K_ALU.vhd:274:27  */
  assign n63 = exec[2]; // extract
  /* TG68K_ALU.vhd:276:38  */
  assign n64 = exe_opcode[9]; // extract
  /* TG68K_ALU.vhd:276:25  */
  assign n66 = n64 ? 8'b00000000 : FlagsSR;
  /* TG68K_ALU.vhd:281:27  */
  assign n67 = exec[77]; // extract
  /* TG68K_ALU.vhd:282:54  */
  assign n68 = n236[11:8]; // extract
  /* TG68K_ALU.vhd:282:78  */
  assign n69 = n236[3:0]; // extract
  /* TG68K_ALU.vhd:282:68  */
  assign n70 = {n68, n69};
  assign n71 = n236[7:0]; // extract
  /* TG68K_ALU.vhd:281:17  */
  assign n72 = n67 ? n70 : n71;
  assign n73 = {n66, n2364};
  assign n74 = n73[7:0]; // extract
  /* TG68K_ALU.vhd:274:17  */
  assign n75 = n63 ? n74 : n72;
  assign n76 = n73[15:8]; // extract
  assign n77 = n236[15:8]; // extract
  /* TG68K_ALU.vhd:274:17  */
  assign n78 = n63 ? n76 : n77;
  assign n79 = {n78, n75};
  assign n80 = bf_datareg[15:0]; // extract
  /* TG68K_ALU.vhd:272:17  */
  assign n81 = n62 ? n80 : n79;
  assign n82 = bf_datareg[31:16]; // extract
  assign n83 = n236[31:16]; // extract
  /* TG68K_ALU.vhd:272:17  */
  assign n84 = n62 ? n82 : n83;
  assign n85 = {n84, n81};
  /* TG68K_ALU.vhd:270:17  */
  assign n86 = n61 ? bits_out : n85;
  /* TG68K_ALU.vhd:268:17  */
  assign n87 = n57 ? n60 : n86;
  /* TG68K_ALU.vhd:266:17  */
  assign n88 = n56 ? bsout : n87;
  /* TG68K_ALU.vhd:264:17  */
  assign n89 = n55 ? rot_out : n88;
  /* TG68K_ALU.vhd:261:17  */
  assign n90 = n54 ? OP2out : n89;
  /* TG68K_ALU.vhd:258:17  */
  assign n91 = n52 ? n53 : n90;
  assign n92 = n91[7:0]; // extract
  /* TG68K_ALU.vhd:256:17  */
  assign n93 = n48 ? n51 : n92;
  assign n94 = n91[31:8]; // extract
  assign n95 = n236[31:8]; // extract
  /* TG68K_ALU.vhd:256:17  */
  assign n96 = n48 ? n95 : n94;
  assign n97 = {n96, n93};
  /* TG68K_ALU.vhd:254:17  */
  assign n98 = n46 ? n47 : n97;
  /* TG68K_ALU.vhd:252:17  */
  assign n99 = n44 ? n45 : n98;
  /* TG68K_ALU.vhd:241:17  */
  assign n100 = n32 ? n43 : n99;
  /* TG68K_ALU.vhd:226:17  */
  assign n101 = n25 ? n29 : n100;
  assign n102 = n101[7:0]; // extract
  /* TG68K_ALU.vhd:224:17  */
  assign n103 = n21 ? n22 : n102;
  assign n104 = n101[31:8]; // extract
  assign n105 = n236[31:8]; // extract
  /* TG68K_ALU.vhd:224:17  */
  assign n106 = n21 ? n105 : n104;
  /* TG68K_ALU.vhd:293:24  */
  assign n111 = exec[29]; // extract
  /* TG68K_ALU.vhd:294:34  */
  assign n112 = sndOPC[11]; // extract
  /* TG68K_ALU.vhd:295:51  */
  assign n113 = OP1out[31]; // extract
  /* TG68K_ALU.vhd:295:62  */
  assign n114 = OP1out[31]; // extract
  /* TG68K_ALU.vhd:295:55  */
  assign n115 = {n113, n114};
  /* TG68K_ALU.vhd:295:73  */
  assign n116 = OP1out[31]; // extract
  /* TG68K_ALU.vhd:295:66  */
  assign n117 = {n115, n116};
  /* TG68K_ALU.vhd:295:84  */
  assign n118 = OP1out[31:3]; // extract
  /* TG68K_ALU.vhd:295:77  */
  assign n119 = {n117, n118};
  /* TG68K_ALU.vhd:297:84  */
  assign n120 = sndOPC[10:9]; // extract
  /* TG68K_ALU.vhd:297:77  */
  assign n122 = {30'b000000000000000000000000000000, n120};
  /* TG68K_ALU.vhd:294:25  */
  assign n123 = n112 ? n119 : n122;
  /* TG68K_ALU.vhd:293:17  */
  assign n124 = n111 ? n123 : OP1out;
  /* TG68K_ALU.vhd:301:24  */
  assign n125 = exec[48]; // extract
  /* TG68K_ALU.vhd:301:17  */
  assign n128 = n125 ? 1'b1 : 1'b0;
  /* TG68K_ALU.vhd:309:24  */
  assign n130 = exec[78]; // extract
  /* TG68K_ALU.vhd:310:65  */
  assign n131 = OP2out[7:4]; // extract
  /* TG68K_ALU.vhd:310:57  */
  assign n133 = {4'b0000, n131};
  /* TG68K_ALU.vhd:310:78  */
  assign n135 = {n133, 4'b0000};
  /* TG68K_ALU.vhd:310:95  */
  assign n136 = OP2out[3:0]; // extract
  /* TG68K_ALU.vhd:310:87  */
  assign n137 = {n135, n136};
  /* TG68K_ALU.vhd:311:30  */
  assign n138 = ~execOPC;
  /* TG68K_ALU.vhd:311:43  */
  assign n139 = exec[53]; // extract
  /* TG68K_ALU.vhd:311:55  */
  assign n140 = ~n139;
  /* TG68K_ALU.vhd:311:35  */
  assign n141 = n140 & n138;
  /* TG68K_ALU.vhd:311:68  */
  assign n142 = exec[29]; // extract
  /* TG68K_ALU.vhd:311:82  */
  assign n143 = ~n142;
  /* TG68K_ALU.vhd:311:60  */
  assign n144 = n143 & n141;
  /* TG68K_ALU.vhd:312:38  */
  assign n145 = ~long_start;
  /* TG68K_ALU.vhd:312:59  */
  assign n147 = exe_datatype == 2'b00;
  /* TG68K_ALU.vhd:312:43  */
  assign n148 = n147 & n145;
  /* TG68K_ALU.vhd:312:73  */
  assign n149 = exec[50]; // extract
  /* TG68K_ALU.vhd:312:81  */
  assign n150 = ~n149;
  /* TG68K_ALU.vhd:312:65  */
  assign n151 = n150 & n148;
  /* TG68K_ALU.vhd:314:41  */
  assign n152 = ~long_start;
  /* TG68K_ALU.vhd:314:62  */
  assign n154 = exe_datatype == 2'b10;
  /* TG68K_ALU.vhd:314:46  */
  assign n155 = n154 & n152;
  /* TG68K_ALU.vhd:314:77  */
  assign n156 = exec[47]; // extract
  /* TG68K_ALU.vhd:314:93  */
  assign n157 = exec[46]; // extract
  /* TG68K_ALU.vhd:314:86  */
  assign n158 = n156 | n157;
  /* TG68K_ALU.vhd:314:103  */
  assign n159 = n158 | movem_presub;
  /* TG68K_ALU.vhd:314:68  */
  assign n160 = n159 & n155;
  /* TG68K_ALU.vhd:315:40  */
  assign n161 = exec[69]; // extract
  /* TG68K_ALU.vhd:315:33  */
  assign n164 = n161 ? 32'b00000000000000000000000000000110 : 32'b00000000000000000000000000000100;
  /* TG68K_ALU.vhd:314:25  */
  assign n166 = n160 ? n164 : 32'b00000000000000000000000000000010;
  /* TG68K_ALU.vhd:312:25  */
  assign n168 = n151 ? 32'b00000000000000000000000000000001 : n166;
  /* TG68K_ALU.vhd:324:33  */
  assign n169 = exec[28]; // extract
  /* TG68K_ALU.vhd:324:59  */
  assign n170 = n2364[4]; // extract
  /* TG68K_ALU.vhd:324:50  */
  assign n171 = n170 & n169;
  /* TG68K_ALU.vhd:324:75  */
  assign n172 = exec[31]; // extract
  /* TG68K_ALU.vhd:324:68  */
  assign n173 = n171 | n172;
  /* TG68K_ALU.vhd:324:25  */
  assign n175 = n173 ? 1'b1 : 1'b0;
  /* TG68K_ALU.vhd:327:41  */
  assign n176 = exec[56]; // extract
  /* TG68K_ALU.vhd:311:17  */
  assign n177 = n144 ? n168 : OP2out;
  /* TG68K_ALU.vhd:311:17  */
  assign n178 = n144 ? n128 : n176;
  /* TG68K_ALU.vhd:311:17  */
  assign n179 = n144 ? 1'b0 : n175;
  assign n180 = n177[15:0]; // extract
  /* TG68K_ALU.vhd:309:17  */
  assign n181 = n130 ? n137 : n180;
  assign n182 = n177[31:16]; // extract
  assign n183 = OP2out[31:16]; // extract
  /* TG68K_ALU.vhd:309:17  */
  assign n184 = n130 ? n183 : n182;
  /* TG68K_ALU.vhd:309:17  */
  assign n186 = n130 ? n128 : n178;
  /* TG68K_ALU.vhd:309:17  */
  assign n187 = n130 ? 1'b0 : n179;
  /* TG68K_ALU.vhd:331:24  */
  assign n188 = exec[69]; // extract
  /* TG68K_ALU.vhd:331:43  */
  assign n189 = n188 | check_aligned;
  /* TG68K_ALU.vhd:332:36  */
  assign n190 = ~movem_presub;
  /* TG68K_ALU.vhd:333:64  */
  assign n191 = ~long_start;
  /* TG68K_ALU.vhd:333:48  */
  assign n192 = n191 & non_aligned;
  assign n194 = {n184, n181};
  /* TG68K_ALU.vhd:333:25  */
  assign n195 = n192 ? 32'b00000000000000000000000000000000 : n194;
  /* TG68K_ALU.vhd:337:64  */
  assign n196 = ~long_start;
  /* TG68K_ALU.vhd:337:48  */
  assign n197 = n196 & non_aligned;
  /* TG68K_ALU.vhd:338:44  */
  assign n199 = exe_datatype == 2'b10;
  /* TG68K_ALU.vhd:338:27  */
  assign n202 = n199 ? 32'b00000000000000000000000000001000 : 32'b00000000000000000000000000000100;
  assign n203 = {n184, n181};
  /* TG68K_ALU.vhd:337:25  */
  assign n204 = n197 ? n202 : n203;
  /* TG68K_ALU.vhd:332:19  */
  assign n205 = n190 ? n195 : n204;
  assign n206 = {n184, n181};
  /* TG68K_ALU.vhd:331:17  */
  assign n207 = n189 ? n205 : n206;
  /* TG68K_ALU.vhd:347:28  */
  assign n208 = ~opaddsub;
  /* TG68K_ALU.vhd:347:33  */
  assign n209 = n208 | long_start;
  /* TG68K_ALU.vhd:348:43  */
  assign n211 = {1'b0, addsub_b};
  /* TG68K_ALU.vhd:348:57  */
  assign n212 = c_in[0]; // extract
  /* TG68K_ALU.vhd:348:52  */
  assign n213 = {n211, n212};
  /* TG68K_ALU.vhd:350:48  */
  assign n215 = {1'b0, addsub_b};
  /* TG68K_ALU.vhd:350:62  */
  assign n216 = c_in[0]; // extract
  /* TG68K_ALU.vhd:350:57  */
  assign n217 = {n215, n216};
  /* TG68K_ALU.vhd:350:40  */
  assign n218 = ~n217;
  /* TG68K_ALU.vhd:347:17  */
  assign n219 = n209 ? n213 : n218;
  /* TG68K_ALU.vhd:352:36  */
  assign n221 = {1'b0, addsub_a};
  /* TG68K_ALU.vhd:352:57  */
  assign n222 = notaddsub_b[0]; // extract
  /* TG68K_ALU.vhd:352:45  */
  assign n223 = {n221, n222};
  /* TG68K_ALU.vhd:352:61  */
  assign n224 = n223 + notaddsub_b;
  /* TG68K_ALU.vhd:353:38  */
  assign n225 = add_result[9]; // extract
  /* TG68K_ALU.vhd:353:54  */
  assign n226 = addsub_a[8]; // extract
  /* TG68K_ALU.vhd:353:42  */
  assign n227 = n225 ^ n226;
  /* TG68K_ALU.vhd:353:70  */
  assign n228 = addsub_b[8]; // extract
  /* TG68K_ALU.vhd:353:58  */
  assign n229 = n227 ^ n228;
  /* TG68K_ALU.vhd:354:38  */
  assign n230 = add_result[17]; // extract
  /* TG68K_ALU.vhd:354:55  */
  assign n231 = addsub_a[16]; // extract
  /* TG68K_ALU.vhd:354:43  */
  assign n232 = n230 ^ n231;
  /* TG68K_ALU.vhd:354:72  */
  assign n233 = addsub_b[16]; // extract
  /* TG68K_ALU.vhd:354:60  */
  assign n234 = n232 ^ n233;
  /* TG68K_ALU.vhd:355:38  */
  assign n235 = add_result[33]; // extract
  /* TG68K_ALU.vhd:356:39  */
  assign n236 = add_result[32:1]; // extract
  /* TG68K_ALU.vhd:357:39  */
  assign n237 = c_in[1]; // extract
  /* TG68K_ALU.vhd:357:57  */
  assign n238 = add_result[8]; // extract
  /* TG68K_ALU.vhd:357:43  */
  assign n239 = n237 ^ n238;
  /* TG68K_ALU.vhd:357:73  */
  assign n240 = addsub_a[7]; // extract
  /* TG68K_ALU.vhd:357:61  */
  assign n241 = n239 ^ n240;
  /* TG68K_ALU.vhd:357:89  */
  assign n242 = addsub_b[7]; // extract
  /* TG68K_ALU.vhd:357:77  */
  assign n243 = n241 ^ n242;
  /* TG68K_ALU.vhd:358:39  */
  assign n244 = c_in[2]; // extract
  /* TG68K_ALU.vhd:358:57  */
  assign n245 = add_result[16]; // extract
  /* TG68K_ALU.vhd:358:43  */
  assign n246 = n244 ^ n245;
  /* TG68K_ALU.vhd:358:74  */
  assign n247 = addsub_a[15]; // extract
  /* TG68K_ALU.vhd:358:62  */
  assign n248 = n246 ^ n247;
  /* TG68K_ALU.vhd:358:91  */
  assign n249 = addsub_b[15]; // extract
  /* TG68K_ALU.vhd:358:79  */
  assign n250 = n248 ^ n249;
  /* TG68K_ALU.vhd:359:39  */
  assign n251 = c_in[3]; // extract
  /* TG68K_ALU.vhd:359:57  */
  assign n252 = add_result[32]; // extract
  /* TG68K_ALU.vhd:359:43  */
  assign n253 = n251 ^ n252;
  /* TG68K_ALU.vhd:359:74  */
  assign n254 = addsub_a[31]; // extract
  /* TG68K_ALU.vhd:359:62  */
  assign n255 = n253 ^ n254;
  /* TG68K_ALU.vhd:359:91  */
  assign n256 = addsub_b[31]; // extract
  /* TG68K_ALU.vhd:359:79  */
  assign n257 = n255 ^ n256;
  /* TG68K_ALU.vhd:360:30  */
  assign n258 = c_in[3:1]; // extract
  /* TG68K_ALU.vhd:370:32  */
  assign n262 = c_in[1]; // extract
  /* TG68K_ALU.vhd:370:46  */
  assign n263 = add_result[8:0]; // extract
  /* TG68K_ALU.vhd:370:35  */
  assign n264 = {n262, n263};
  /* TG68K_ALU.vhd:372:38  */
  assign n265 = OP1out[4]; // extract
  /* TG68K_ALU.vhd:372:52  */
  assign n266 = OP2out[4]; // extract
  /* TG68K_ALU.vhd:372:42  */
  assign n267 = n265 ^ n266;
  /* TG68K_ALU.vhd:372:67  */
  assign n268 = bcd_pur[5]; // extract
  /* TG68K_ALU.vhd:372:56  */
  assign n269 = n267 ^ n268;
  /* TG68K_ALU.vhd:373:17  */
  assign n272 = halve_carry ? 4'b0110 : 4'b0000;
  /* TG68K_ALU.vhd:376:27  */
  assign n275 = bcd_pur[9]; // extract
  assign n277 = n273[7:4]; // extract
  /* TG68K_ALU.vhd:376:17  */
  assign n278 = n275 ? 4'b0110 : n277;
  assign n279 = n273[8]; // extract
  /* TG68K_ALU.vhd:379:24  */
  assign n280 = exec[12]; // extract
  /* TG68K_ALU.vhd:380:47  */
  assign n281 = bcd_pur[8]; // extract
  /* TG68K_ALU.vhd:380:36  */
  assign n282 = ~n281;
  /* TG68K_ALU.vhd:380:60  */
  assign n283 = bcd_a[7]; // extract
  /* TG68K_ALU.vhd:380:51  */
  assign n284 = n282 & n283;
  /* TG68K_ALU.vhd:382:41  */
  assign n285 = bcd_pur[9:1]; // extract
  /* TG68K_ALU.vhd:382:54  */
  assign n286 = n285 + bcd_kor;
  /* TG68K_ALU.vhd:383:36  */
  assign n287 = bcd_pur[4]; // extract
  /* TG68K_ALU.vhd:383:52  */
  assign n288 = bcd_pur[3]; // extract
  /* TG68K_ALU.vhd:383:66  */
  assign n289 = bcd_pur[2]; // extract
  /* TG68K_ALU.vhd:383:56  */
  assign n290 = n288 | n289;
  /* TG68K_ALU.vhd:383:40  */
  assign n291 = n287 & n290;
  /* TG68K_ALU.vhd:383:25  */
  assign n293 = n291 ? 4'b0110 : n272;
  /* TG68K_ALU.vhd:386:36  */
  assign n294 = bcd_pur[8]; // extract
  /* TG68K_ALU.vhd:386:52  */
  assign n295 = bcd_pur[7]; // extract
  /* TG68K_ALU.vhd:386:66  */
  assign n296 = bcd_pur[6]; // extract
  /* TG68K_ALU.vhd:386:56  */
  assign n297 = n295 | n296;
  /* TG68K_ALU.vhd:386:81  */
  assign n298 = bcd_pur[5]; // extract
  /* TG68K_ALU.vhd:386:96  */
  assign n299 = bcd_pur[4]; // extract
  /* TG68K_ALU.vhd:386:85  */
  assign n300 = n298 & n299;
  /* TG68K_ALU.vhd:386:112  */
  assign n301 = bcd_pur[3]; // extract
  /* TG68K_ALU.vhd:386:126  */
  assign n302 = bcd_pur[2]; // extract
  /* TG68K_ALU.vhd:386:116  */
  assign n303 = n301 | n302;
  /* TG68K_ALU.vhd:386:100  */
  assign n304 = n300 & n303;
  /* TG68K_ALU.vhd:386:70  */
  assign n305 = n297 | n304;
  /* TG68K_ALU.vhd:386:40  */
  assign n306 = n294 & n305;
  /* TG68K_ALU.vhd:386:25  */
  assign n308 = n306 ? 4'b0110 : n278;
  /* TG68K_ALU.vhd:390:43  */
  assign n309 = bcd_pur[8]; // extract
  /* TG68K_ALU.vhd:390:60  */
  assign n310 = bcd_a[7]; // extract
  /* TG68K_ALU.vhd:390:51  */
  assign n311 = ~n310;
  /* TG68K_ALU.vhd:390:47  */
  assign n312 = n309 & n311;
  /* TG68K_ALU.vhd:392:41  */
  assign n313 = bcd_pur[9:1]; // extract
  /* TG68K_ALU.vhd:392:54  */
  assign n314 = n313 - bcd_kor;
  assign n315 = {n308, n293};
  assign n316 = {n278, n272};
  /* TG68K_ALU.vhd:379:17  */
  assign n317 = n280 ? n315 : n316;
  /* TG68K_ALU.vhd:379:17  */
  assign n318 = n280 ? n284 : n312;
  /* TG68K_ALU.vhd:379:17  */
  assign n319 = n280 ? n286 : n314;
  /* TG68K_ALU.vhd:394:23  */
  assign n320 = CPU[1]; // extract
  /* TG68K_ALU.vhd:394:17  */
  assign n322 = n320 ? 1'b0 : n318;
  /* TG68K_ALU.vhd:397:39  */
  assign n323 = bcd_pur[9]; // extract
  /* TG68K_ALU.vhd:397:51  */
  assign n324 = bcd_a[8]; // extract
  /* TG68K_ALU.vhd:397:43  */
  assign n325 = n323 | n324;
  /* TG68K_ALU.vhd:409:44  */
  assign n330 = opcode[7:6]; // extract
  /* TG68K_ALU.vhd:410:41  */
  assign n332 = n330 == 2'b01;
  /* TG68K_ALU.vhd:412:41  */
  assign n334 = n330 == 2'b11;
  assign n335 = {n334, n332};
  /* TG68K_ALU.vhd:409:33  */
  always @*
    case (n335)
      2'b10: n338 = 1'b0;
      2'b01: n338 = 1'b1;
      default: n338 = 1'b0;
    endcase
  /* TG68K_ALU.vhd:409:33  */
  always @*
    case (n335)
      2'b10: n342 = 1'b1;
      2'b01: n342 = 1'b0;
      default: n342 = 1'b0;
    endcase
  /* TG68K_ALU.vhd:419:30  */
  assign n348 = exe_opcode[8]; // extract
  /* TG68K_ALU.vhd:419:33  */
  assign n349 = ~n348;
  /* TG68K_ALU.vhd:420:38  */
  assign n350 = exe_opcode[5:4]; // extract
  /* TG68K_ALU.vhd:420:50  */
  assign n352 = n350 == 2'b00;
  /* TG68K_ALU.vhd:421:53  */
  assign n353 = sndOPC[4:0]; // extract
  /* TG68K_ALU.vhd:423:58  */
  assign n354 = sndOPC[2:0]; // extract
  /* TG68K_ALU.vhd:423:51  */
  assign n356 = {2'b00, n354};
  /* TG68K_ALU.vhd:420:25  */
  assign n357 = n352 ? n353 : n356;
  /* TG68K_ALU.vhd:426:38  */
  assign n358 = exe_opcode[5:4]; // extract
  /* TG68K_ALU.vhd:426:50  */
  assign n360 = n358 == 2'b00;
  /* TG68K_ALU.vhd:427:53  */
  assign n361 = reg_QB[4:0]; // extract
  /* TG68K_ALU.vhd:429:58  */
  assign n362 = reg_QB[2:0]; // extract
  /* TG68K_ALU.vhd:429:51  */
  assign n364 = {2'b00, n362};
  /* TG68K_ALU.vhd:426:25  */
  assign n365 = n360 ? n361 : n364;
  /* TG68K_ALU.vhd:419:17  */
  assign n366 = n349 ? n357 : n365;
  /* TG68K_ALU.vhd:435:65  */
  assign n372 = ~one_bit_in;
  /* TG68K_ALU.vhd:435:61  */
  assign n373 = bchg & n372;
  /* TG68K_ALU.vhd:435:81  */
  assign n374 = n373 | bset;
  /* TG68K_ALU.vhd:456:42  */
  assign n380 = opcode[5:4]; // extract
  /* TG68K_ALU.vhd:456:55  */
  assign n382 = n380 == 2'b00;
  /* TG68K_ALU.vhd:456:33  */
  assign n385 = n382 ? 1'b1 : 1'b0;
  /* TG68K_ALU.vhd:459:44  */
  assign n387 = opcode[10:8]; // extract
  /* TG68K_ALU.vhd:460:41  */
  assign n389 = n387 == 3'b010;
  /* TG68K_ALU.vhd:461:41  */
  assign n391 = n387 == 3'b011;
  /* TG68K_ALU.vhd:463:41  */
  assign n393 = n387 == 3'b101;
  /* TG68K_ALU.vhd:464:41  */
  assign n395 = n387 == 3'b110;
  /* TG68K_ALU.vhd:465:41  */
  assign n397 = n387 == 3'b111;
  assign n398 = {n397, n395, n393, n391, n389};
  /* TG68K_ALU.vhd:459:33  */
  always @*
    case (n398)
      5'b10000: n401 = 1'b0;
      5'b01000: n401 = 1'b1;
      5'b00100: n401 = 1'b0;
      5'b00010: n401 = 1'b0;
      5'b00001: n401 = 1'b0;
      default: n401 = 1'b0;
    endcase
  /* TG68K_ALU.vhd:459:33  */
  always @*
    case (n398)
      5'b10000: n405 = 1'b0;
      5'b01000: n405 = 1'b0;
      5'b00100: n405 = 1'b0;
      5'b00010: n405 = 1'b0;
      5'b00001: n405 = 1'b1;
      default: n405 = 1'b0;
    endcase
  /* TG68K_ALU.vhd:459:33  */
  always @*
    case (n398)
      5'b10000: n409 = 1'b1;
      5'b01000: n409 = 1'b0;
      5'b00100: n409 = 1'b0;
      5'b00010: n409 = 1'b0;
      5'b00001: n409 = 1'b0;
      default: n409 = 1'b0;
    endcase
  /* TG68K_ALU.vhd:459:33  */
  always @*
    case (n398)
      5'b10000: n413 = 1'b0;
      5'b01000: n413 = 1'b0;
      5'b00100: n413 = 1'b0;
      5'b00010: n413 = 1'b1;
      5'b00001: n413 = 1'b0;
      default: n413 = 1'b0;
    endcase
  /* TG68K_ALU.vhd:459:33  */
  always @*
    case (n398)
      5'b10000: n417 = 1'b0;
      5'b01000: n417 = 1'b0;
      5'b00100: n417 = 1'b1;
      5'b00010: n417 = 1'b0;
      5'b00001: n417 = 1'b0;
      default: n417 = 1'b0;
    endcase
  /* TG68K_ALU.vhd:459:33  */
  always @*
    case (n398)
      5'b10000: n420 = 1'b1;
      5'b01000: n420 = n385;
      5'b00100: n420 = n385;
      5'b00010: n420 = n385;
      5'b00001: n420 = n385;
      default: n420 = n385;
    endcase
  /* TG68K_ALU.vhd:469:42  */
  assign n421 = opcode[4:3]; // extract
  /* TG68K_ALU.vhd:469:54  */
  assign n423 = n421 == 2'b00;
  /* TG68K_ALU.vhd:469:33  */
  assign n426 = n423 ? 1'b1 : 1'b0;
  /* TG68K_ALU.vhd:472:53  */
  assign n428 = result[39:32]; // extract
  /* TG68K_ALU.vhd:476:17  */
  assign n445 = bf_ins ? reg_QB : bf_set2;
  /* TG68K_ALU.vhd:490:38  */
  assign n446 = bf_width[4:0]; // extract
  /* TG68K_ALU.vhd:490:29  */
  assign n448 = $unsigned(5'b00000) > $unsigned(n446);
  assign n451 = n445[0]; // extract
  /* TG68K_ALU.vhd:490:25  */
  assign n452 = n448 ? 1'b0 : n451;
  /* TG68K_ALU.vhd:490:25  */
  assign n455 = n448 ? 1'b1 : 1'b0;
  /* TG68K_ALU.vhd:490:38  */
  assign n458 = bf_width[4:0]; // extract
  /* TG68K_ALU.vhd:490:29  */
  assign n460 = $unsigned(5'b00001) > $unsigned(n458);
  assign n463 = n445[1]; // extract
  /* TG68K_ALU.vhd:490:25  */
  assign n464 = n460 ? 1'b0 : n463;
  assign n466 = n456[1]; // extract
  /* TG68K_ALU.vhd:490:25  */
  assign n467 = n460 ? 1'b1 : n466;
  /* TG68K_ALU.vhd:490:38  */
  assign n469 = bf_width[4:0]; // extract
  /* TG68K_ALU.vhd:490:29  */
  assign n471 = $unsigned(5'b00010) > $unsigned(n469);
  assign n474 = n445[2]; // extract
  /* TG68K_ALU.vhd:490:25  */
  assign n475 = n471 ? 1'b0 : n474;
  assign n477 = n456[2]; // extract
  /* TG68K_ALU.vhd:490:25  */
  assign n478 = n471 ? 1'b1 : n477;
  /* TG68K_ALU.vhd:490:38  */
  assign n480 = bf_width[4:0]; // extract
  /* TG68K_ALU.vhd:490:29  */
  assign n482 = $unsigned(5'b00011) > $unsigned(n480);
  assign n485 = n445[3]; // extract
  /* TG68K_ALU.vhd:490:25  */
  assign n486 = n482 ? 1'b0 : n485;
  assign n488 = n456[3]; // extract
  /* TG68K_ALU.vhd:490:25  */
  assign n489 = n482 ? 1'b1 : n488;
  /* TG68K_ALU.vhd:490:38  */
  assign n491 = bf_width[4:0]; // extract
  /* TG68K_ALU.vhd:490:29  */
  assign n493 = $unsigned(5'b00100) > $unsigned(n491);
  assign n496 = n445[4]; // extract
  /* TG68K_ALU.vhd:490:25  */
  assign n497 = n493 ? 1'b0 : n496;
  assign n499 = n456[4]; // extract
  /* TG68K_ALU.vhd:490:25  */
  assign n500 = n493 ? 1'b1 : n499;
  /* TG68K_ALU.vhd:490:38  */
  assign n502 = bf_width[4:0]; // extract
  /* TG68K_ALU.vhd:490:29  */
  assign n504 = $unsigned(5'b00101) > $unsigned(n502);
  assign n507 = n445[5]; // extract
  /* TG68K_ALU.vhd:490:25  */
  assign n508 = n504 ? 1'b0 : n507;
  assign n510 = n456[5]; // extract
  /* TG68K_ALU.vhd:490:25  */
  assign n511 = n504 ? 1'b1 : n510;
  /* TG68K_ALU.vhd:490:38  */
  assign n513 = bf_width[4:0]; // extract
  /* TG68K_ALU.vhd:490:29  */
  assign n515 = $unsigned(5'b00110) > $unsigned(n513);
  assign n518 = n445[6]; // extract
  /* TG68K_ALU.vhd:490:25  */
  assign n519 = n515 ? 1'b0 : n518;
  assign n521 = n456[6]; // extract
  /* TG68K_ALU.vhd:490:25  */
  assign n522 = n515 ? 1'b1 : n521;
  /* TG68K_ALU.vhd:490:38  */
  assign n524 = bf_width[4:0]; // extract
  /* TG68K_ALU.vhd:490:29  */
  assign n526 = $unsigned(5'b00111) > $unsigned(n524);
  assign n529 = n445[7]; // extract
  /* TG68K_ALU.vhd:490:25  */
  assign n530 = n526 ? 1'b0 : n529;
  assign n532 = n456[7]; // extract
  /* TG68K_ALU.vhd:490:25  */
  assign n533 = n526 ? 1'b1 : n532;
  /* TG68K_ALU.vhd:490:38  */
  assign n535 = bf_width[4:0]; // extract
  /* TG68K_ALU.vhd:490:29  */
  assign n537 = $unsigned(5'b01000) > $unsigned(n535);
  assign n540 = n445[8]; // extract
  /* TG68K_ALU.vhd:490:25  */
  assign n541 = n537 ? 1'b0 : n540;
  assign n543 = n456[8]; // extract
  /* TG68K_ALU.vhd:490:25  */
  assign n544 = n537 ? 1'b1 : n543;
  /* TG68K_ALU.vhd:490:38  */
  assign n546 = bf_width[4:0]; // extract
  /* TG68K_ALU.vhd:490:29  */
  assign n548 = $unsigned(5'b01001) > $unsigned(n546);
  assign n551 = n445[9]; // extract
  /* TG68K_ALU.vhd:490:25  */
  assign n552 = n548 ? 1'b0 : n551;
  assign n554 = n456[9]; // extract
  /* TG68K_ALU.vhd:490:25  */
  assign n555 = n548 ? 1'b1 : n554;
  /* TG68K_ALU.vhd:490:38  */
  assign n557 = bf_width[4:0]; // extract
  /* TG68K_ALU.vhd:490:29  */
  assign n559 = $unsigned(5'b01010) > $unsigned(n557);
  assign n562 = n445[10]; // extract
  /* TG68K_ALU.vhd:490:25  */
  assign n563 = n559 ? 1'b0 : n562;
  assign n565 = n456[10]; // extract
  /* TG68K_ALU.vhd:490:25  */
  assign n566 = n559 ? 1'b1 : n565;
  /* TG68K_ALU.vhd:490:38  */
  assign n568 = bf_width[4:0]; // extract
  /* TG68K_ALU.vhd:490:29  */
  assign n570 = $unsigned(5'b01011) > $unsigned(n568);
  assign n573 = n445[11]; // extract
  /* TG68K_ALU.vhd:490:25  */
  assign n574 = n570 ? 1'b0 : n573;
  assign n576 = n456[11]; // extract
  /* TG68K_ALU.vhd:490:25  */
  assign n577 = n570 ? 1'b1 : n576;
  /* TG68K_ALU.vhd:490:38  */
  assign n579 = bf_width[4:0]; // extract
  /* TG68K_ALU.vhd:490:29  */
  assign n581 = $unsigned(5'b01100) > $unsigned(n579);
  assign n584 = n445[12]; // extract
  /* TG68K_ALU.vhd:490:25  */
  assign n585 = n581 ? 1'b0 : n584;
  assign n587 = n456[12]; // extract
  /* TG68K_ALU.vhd:490:25  */
  assign n588 = n581 ? 1'b1 : n587;
  /* TG68K_ALU.vhd:490:38  */
  assign n590 = bf_width[4:0]; // extract
  /* TG68K_ALU.vhd:490:29  */
  assign n592 = $unsigned(5'b01101) > $unsigned(n590);
  assign n595 = n445[13]; // extract
  /* TG68K_ALU.vhd:490:25  */
  assign n596 = n592 ? 1'b0 : n595;
  assign n598 = n456[13]; // extract
  /* TG68K_ALU.vhd:490:25  */
  assign n599 = n592 ? 1'b1 : n598;
  /* TG68K_ALU.vhd:490:38  */
  assign n601 = bf_width[4:0]; // extract
  /* TG68K_ALU.vhd:490:29  */
  assign n603 = $unsigned(5'b01110) > $unsigned(n601);
  assign n606 = n445[14]; // extract
  /* TG68K_ALU.vhd:490:25  */
  assign n607 = n603 ? 1'b0 : n606;
  assign n609 = n456[14]; // extract
  /* TG68K_ALU.vhd:490:25  */
  assign n610 = n603 ? 1'b1 : n609;
  /* TG68K_ALU.vhd:490:38  */
  assign n612 = bf_width[4:0]; // extract
  /* TG68K_ALU.vhd:490:29  */
  assign n614 = $unsigned(5'b01111) > $unsigned(n612);
  assign n617 = n445[15]; // extract
  /* TG68K_ALU.vhd:490:25  */
  assign n618 = n614 ? 1'b0 : n617;
  assign n620 = n456[15]; // extract
  /* TG68K_ALU.vhd:490:25  */
  assign n621 = n614 ? 1'b1 : n620;
  /* TG68K_ALU.vhd:490:38  */
  assign n623 = bf_width[4:0]; // extract
  /* TG68K_ALU.vhd:490:29  */
  assign n625 = $unsigned(5'b10000) > $unsigned(n623);
  assign n628 = n445[16]; // extract
  /* TG68K_ALU.vhd:490:25  */
  assign n629 = n625 ? 1'b0 : n628;
  assign n631 = n456[16]; // extract
  /* TG68K_ALU.vhd:490:25  */
  assign n632 = n625 ? 1'b1 : n631;
  /* TG68K_ALU.vhd:490:38  */
  assign n634 = bf_width[4:0]; // extract
  /* TG68K_ALU.vhd:490:29  */
  assign n636 = $unsigned(5'b10001) > $unsigned(n634);
  assign n639 = n445[17]; // extract
  /* TG68K_ALU.vhd:490:25  */
  assign n640 = n636 ? 1'b0 : n639;
  assign n642 = n456[17]; // extract
  /* TG68K_ALU.vhd:490:25  */
  assign n643 = n636 ? 1'b1 : n642;
  /* TG68K_ALU.vhd:490:38  */
  assign n645 = bf_width[4:0]; // extract
  /* TG68K_ALU.vhd:490:29  */
  assign n647 = $unsigned(5'b10010) > $unsigned(n645);
  assign n650 = n445[18]; // extract
  /* TG68K_ALU.vhd:490:25  */
  assign n651 = n647 ? 1'b0 : n650;
  assign n653 = n456[18]; // extract
  /* TG68K_ALU.vhd:490:25  */
  assign n654 = n647 ? 1'b1 : n653;
  /* TG68K_ALU.vhd:490:38  */
  assign n656 = bf_width[4:0]; // extract
  /* TG68K_ALU.vhd:490:29  */
  assign n658 = $unsigned(5'b10011) > $unsigned(n656);
  assign n661 = n445[19]; // extract
  /* TG68K_ALU.vhd:490:25  */
  assign n662 = n658 ? 1'b0 : n661;
  assign n664 = n456[19]; // extract
  /* TG68K_ALU.vhd:490:25  */
  assign n665 = n658 ? 1'b1 : n664;
  /* TG68K_ALU.vhd:490:38  */
  assign n667 = bf_width[4:0]; // extract
  /* TG68K_ALU.vhd:490:29  */
  assign n669 = $unsigned(5'b10100) > $unsigned(n667);
  assign n672 = n445[20]; // extract
  /* TG68K_ALU.vhd:490:25  */
  assign n673 = n669 ? 1'b0 : n672;
  assign n675 = n456[20]; // extract
  /* TG68K_ALU.vhd:490:25  */
  assign n676 = n669 ? 1'b1 : n675;
  /* TG68K_ALU.vhd:490:38  */
  assign n678 = bf_width[4:0]; // extract
  /* TG68K_ALU.vhd:490:29  */
  assign n680 = $unsigned(5'b10101) > $unsigned(n678);
  assign n683 = n445[21]; // extract
  /* TG68K_ALU.vhd:490:25  */
  assign n684 = n680 ? 1'b0 : n683;
  assign n686 = n456[21]; // extract
  /* TG68K_ALU.vhd:490:25  */
  assign n687 = n680 ? 1'b1 : n686;
  /* TG68K_ALU.vhd:490:38  */
  assign n689 = bf_width[4:0]; // extract
  /* TG68K_ALU.vhd:490:29  */
  assign n691 = $unsigned(5'b10110) > $unsigned(n689);
  assign n694 = n445[22]; // extract
  /* TG68K_ALU.vhd:490:25  */
  assign n695 = n691 ? 1'b0 : n694;
  assign n697 = n456[22]; // extract
  /* TG68K_ALU.vhd:490:25  */
  assign n698 = n691 ? 1'b1 : n697;
  /* TG68K_ALU.vhd:490:38  */
  assign n700 = bf_width[4:0]; // extract
  /* TG68K_ALU.vhd:490:29  */
  assign n702 = $unsigned(5'b10111) > $unsigned(n700);
  assign n705 = n445[23]; // extract
  /* TG68K_ALU.vhd:490:25  */
  assign n706 = n702 ? 1'b0 : n705;
  assign n708 = n456[23]; // extract
  /* TG68K_ALU.vhd:490:25  */
  assign n709 = n702 ? 1'b1 : n708;
  /* TG68K_ALU.vhd:490:38  */
  assign n711 = bf_width[4:0]; // extract
  /* TG68K_ALU.vhd:490:29  */
  assign n713 = $unsigned(5'b11000) > $unsigned(n711);
  assign n716 = n445[24]; // extract
  /* TG68K_ALU.vhd:490:25  */
  assign n717 = n713 ? 1'b0 : n716;
  assign n719 = n456[24]; // extract
  /* TG68K_ALU.vhd:490:25  */
  assign n720 = n713 ? 1'b1 : n719;
  /* TG68K_ALU.vhd:490:38  */
  assign n722 = bf_width[4:0]; // extract
  /* TG68K_ALU.vhd:490:29  */
  assign n724 = $unsigned(5'b11001) > $unsigned(n722);
  assign n727 = n445[25]; // extract
  /* TG68K_ALU.vhd:490:25  */
  assign n728 = n724 ? 1'b0 : n727;
  assign n730 = n456[25]; // extract
  /* TG68K_ALU.vhd:490:25  */
  assign n731 = n724 ? 1'b1 : n730;
  /* TG68K_ALU.vhd:490:38  */
  assign n733 = bf_width[4:0]; // extract
  /* TG68K_ALU.vhd:490:29  */
  assign n735 = $unsigned(5'b11010) > $unsigned(n733);
  assign n738 = n445[26]; // extract
  /* TG68K_ALU.vhd:490:25  */
  assign n739 = n735 ? 1'b0 : n738;
  assign n741 = n456[26]; // extract
  /* TG68K_ALU.vhd:490:25  */
  assign n742 = n735 ? 1'b1 : n741;
  /* TG68K_ALU.vhd:490:38  */
  assign n744 = bf_width[4:0]; // extract
  /* TG68K_ALU.vhd:490:29  */
  assign n746 = $unsigned(5'b11011) > $unsigned(n744);
  assign n749 = n445[27]; // extract
  /* TG68K_ALU.vhd:490:25  */
  assign n750 = n746 ? 1'b0 : n749;
  assign n752 = n456[27]; // extract
  /* TG68K_ALU.vhd:490:25  */
  assign n753 = n746 ? 1'b1 : n752;
  /* TG68K_ALU.vhd:490:38  */
  assign n755 = bf_width[4:0]; // extract
  /* TG68K_ALU.vhd:490:29  */
  assign n757 = $unsigned(5'b11100) > $unsigned(n755);
  assign n760 = n445[28]; // extract
  /* TG68K_ALU.vhd:490:25  */
  assign n761 = n757 ? 1'b0 : n760;
  assign n763 = n456[28]; // extract
  /* TG68K_ALU.vhd:490:25  */
  assign n764 = n757 ? 1'b1 : n763;
  /* TG68K_ALU.vhd:490:38  */
  assign n766 = bf_width[4:0]; // extract
  /* TG68K_ALU.vhd:490:29  */
  assign n768 = $unsigned(5'b11101) > $unsigned(n766);
  assign n771 = n445[29]; // extract
  /* TG68K_ALU.vhd:490:25  */
  assign n772 = n768 ? 1'b0 : n771;
  assign n774 = n456[29]; // extract
  /* TG68K_ALU.vhd:490:25  */
  assign n775 = n768 ? 1'b1 : n774;
  /* TG68K_ALU.vhd:490:38  */
  assign n777 = bf_width[4:0]; // extract
  /* TG68K_ALU.vhd:490:29  */
  assign n779 = $unsigned(5'b11110) > $unsigned(n777);
  assign n782 = n445[30]; // extract
  /* TG68K_ALU.vhd:490:25  */
  assign n783 = n779 ? 1'b0 : n782;
  assign n784 = n445[31]; // extract
  assign n785 = n456[30]; // extract
  /* TG68K_ALU.vhd:490:25  */
  assign n786 = n779 ? 1'b1 : n785;
  assign n787 = n456[31]; // extract
  /* TG68K_ALU.vhd:490:38  */
  assign n788 = bf_width[4:0]; // extract
  /* TG68K_ALU.vhd:490:29  */
  assign n790 = $unsigned(5'b11111) > $unsigned(n788);
  /* TG68K_ALU.vhd:490:25  */
  assign n793 = n790 ? 1'b0 : n784;
  /* TG68K_ALU.vhd:490:25  */
  assign n794 = n790 ? 1'b1 : n787;
  /* TG68K_ALU.vhd:496:37  */
  assign n796 = bf_width[4:0];  // trunc
  /* TG68K_ALU.vhd:497:32  */
  assign n799 = bf_nflag & bf_exts;
  /* TG68K_ALU.vhd:498:47  */
  assign n800 = datareg | unshifted_bitmask;
  /* TG68K_ALU.vhd:497:17  */
  assign n801 = n799 ? n800 : datareg;
  /* TG68K_ALU.vhd:504:30  */
  assign n802 = bf_loffset[4]; // extract
  /* TG68K_ALU.vhd:505:57  */
  assign n803 = unshifted_bitmask[15:0]; // extract
  /* TG68K_ALU.vhd:505:88  */
  assign n804 = unshifted_bitmask[31:16]; // extract
  /* TG68K_ALU.vhd:505:70  */
  assign n805 = {n803, n804};
  /* TG68K_ALU.vhd:504:17  */
  assign n806 = n802 ? n805 : unshifted_bitmask;
  /* TG68K_ALU.vhd:509:30  */
  assign n807 = bf_loffset[3]; // extract
  /* TG68K_ALU.vhd:510:64  */
  assign n808 = bitmaskmux3[23:0]; // extract
  /* TG68K_ALU.vhd:510:89  */
  assign n809 = bitmaskmux3[31:24]; // extract
  /* TG68K_ALU.vhd:510:77  */
  assign n810 = {n808, n809};
  /* TG68K_ALU.vhd:509:17  */
  assign n811 = n807 ? n810 : bitmaskmux3;
  /* TG68K_ALU.vhd:514:30  */
  assign n812 = bf_loffset[2]; // extract
  /* TG68K_ALU.vhd:515:51  */
  assign n814 = {bitmaskmux2, 4'b1111};
  /* TG68K_ALU.vhd:517:71  */
  assign n815 = bitmaskmux2[31:28]; // extract
  assign n816 = n814[3:0]; // extract
  /* TG68K_ALU.vhd:516:25  */
  assign n817 = bf_d32 ? n815 : n816;
  assign n818 = n814[35:4]; // extract
  /* TG68K_ALU.vhd:520:46  */
  assign n820 = {4'b1111, bitmaskmux2};
  assign n821 = {n818, n817};
  /* TG68K_ALU.vhd:514:17  */
  assign n822 = n812 ? n821 : n820;
  /* TG68K_ALU.vhd:522:30  */
  assign n823 = bf_loffset[1]; // extract
  /* TG68K_ALU.vhd:523:51  */
  assign n825 = {bitmaskmux1, 2'b11};
  /* TG68K_ALU.vhd:525:71  */
  assign n826 = bitmaskmux1[31:30]; // extract
  assign n827 = n825[1:0]; // extract
  /* TG68K_ALU.vhd:524:25  */
  assign n828 = bf_d32 ? n826 : n827;
  assign n829 = n825[37:2]; // extract
  /* TG68K_ALU.vhd:528:44  */
  assign n831 = {2'b11, bitmaskmux1};
  assign n832 = {n829, n828};
  /* TG68K_ALU.vhd:522:17  */
  assign n833 = n823 ? n832 : n831;
  /* TG68K_ALU.vhd:530:30  */
  assign n834 = bf_loffset[0]; // extract
  /* TG68K_ALU.vhd:531:47  */
  assign n836 = {1'b1, bitmaskmux0};
  /* TG68K_ALU.vhd:531:59  */
  assign n838 = {n836, 1'b1};
  /* TG68K_ALU.vhd:533:66  */
  assign n839 = bitmaskmux0[31]; // extract
  assign n840 = n838[0]; // extract
  /* TG68K_ALU.vhd:532:25  */
  assign n841 = bf_d32 ? n839 : n840;
  assign n842 = n838[39:1]; // extract
  /* TG68K_ALU.vhd:536:48  */
  assign n844 = {2'b11, bitmaskmux0};
  assign n845 = {n842, n841};
  /* TG68K_ALU.vhd:530:17  */
  assign n846 = n834 ? n845 : n844;
  /* TG68K_ALU.vhd:541:35  */
  assign n847 = {bf_ext_in, OP2out};
  /* TG68K_ALU.vhd:543:54  */
  assign n848 = OP2out[7:0]; // extract
  assign n849 = n847[39:32]; // extract
  /* TG68K_ALU.vhd:542:17  */
  assign n850 = bf_s32 ? n848 : n849;
  assign n851 = n847[31:0]; // extract
  /* TG68K_ALU.vhd:546:28  */
  assign n852 = bf_shift[0]; // extract
  /* TG68K_ALU.vhd:547:40  */
  assign n853 = shift[0]; // extract
  /* TG68K_ALU.vhd:547:49  */
  assign n854 = shift[39:1]; // extract
  /* TG68K_ALU.vhd:547:43  */
  assign n855 = {n853, n854};
  /* TG68K_ALU.vhd:546:17  */
  assign n856 = n852 ? n855 : shift;
  /* TG68K_ALU.vhd:551:28  */
  assign n857 = bf_shift[1]; // extract
  /* TG68K_ALU.vhd:552:41  */
  assign n858 = inmux0[1:0]; // extract
  /* TG68K_ALU.vhd:552:60  */
  assign n859 = inmux0[39:2]; // extract
  /* TG68K_ALU.vhd:552:53  */
  assign n860 = {n858, n859};
  /* TG68K_ALU.vhd:551:17  */
  assign n861 = n857 ? n860 : inmux0;
  /* TG68K_ALU.vhd:556:28  */
  assign n862 = bf_shift[2]; // extract
  /* TG68K_ALU.vhd:557:41  */
  assign n863 = inmux1[3:0]; // extract
  /* TG68K_ALU.vhd:557:60  */
  assign n864 = inmux1[39:4]; // extract
  /* TG68K_ALU.vhd:557:53  */
  assign n865 = {n863, n864};
  /* TG68K_ALU.vhd:556:17  */
  assign n866 = n862 ? n865 : inmux1;
  /* TG68K_ALU.vhd:561:28  */
  assign n867 = bf_shift[3]; // extract
  /* TG68K_ALU.vhd:562:41  */
  assign n868 = inmux2[7:0]; // extract
  /* TG68K_ALU.vhd:562:60  */
  assign n869 = inmux2[31:8]; // extract
  /* TG68K_ALU.vhd:562:53  */
  assign n870 = {n868, n869};
  /* TG68K_ALU.vhd:564:41  */
  assign n871 = inmux2[31:0]; // extract
  /* TG68K_ALU.vhd:561:17  */
  assign n872 = n867 ? n870 : n871;
  /* TG68K_ALU.vhd:566:28  */
  assign n873 = bf_shift[4]; // extract
  /* TG68K_ALU.vhd:567:55  */
  assign n874 = inmux3[15:0]; // extract
  /* TG68K_ALU.vhd:567:75  */
  assign n875 = inmux3[31:16]; // extract
  /* TG68K_ALU.vhd:567:68  */
  assign n876 = {n874, n875};
  /* TG68K_ALU.vhd:566:17  */
  assign n877 = n873 ? n876 : inmux3;
  /* TG68K_ALU.vhd:574:56  */
  assign n878 = bf_set2[7:0]; // extract
  /* TG68K_ALU.vhd:576:48  */
  assign n879 = ~OP2out;
  /* TG68K_ALU.vhd:577:49  */
  assign n880 = ~bf_ext_in;
  assign n881 = {n880, n879};
  /* TG68K_ALU.vhd:575:17  */
  assign n883 = bf_bchg ? n881 : 40'b0000000000000000000000000000000000000000;
  assign n884 = {n878, bf_set2};
  /* TG68K_ALU.vhd:572:17  */
  assign n885 = bf_ins ? n884 : n883;
  /* TG68K_ALU.vhd:581:17  */
  assign n887 = bf_bset ? 40'b1111111111111111111111111111111111111111 : n885;
  /* TG68K_ALU.vhd:586:48  */
  assign n888 = {bf_ext_in, OP1out};
  /* TG68K_ALU.vhd:588:48  */
  assign n889 = {bf_ext_in, OP2out};
  /* TG68K_ALU.vhd:585:17  */
  assign n890 = bf_ins ? n888 : n889;
  /* TG68K_ALU.vhd:591:43  */
  assign n891 = shifted_bitmask[0]; // extract
  /* TG68K_ALU.vhd:592:56  */
  assign n892 = result_tmp[0]; // extract
  assign n893 = n887[0]; // extract
  /* TG68K_ALU.vhd:591:25  */
  assign n894 = n891 ? n892 : n893;
  /* TG68K_ALU.vhd:591:43  */
  assign n896 = shifted_bitmask[1]; // extract
  /* TG68K_ALU.vhd:592:56  */
  assign n897 = result_tmp[1]; // extract
  assign n898 = n887[1]; // extract
  /* TG68K_ALU.vhd:591:25  */
  assign n899 = n896 ? n897 : n898;
  /* TG68K_ALU.vhd:591:43  */
  assign n901 = shifted_bitmask[2]; // extract
  /* TG68K_ALU.vhd:592:56  */
  assign n902 = result_tmp[2]; // extract
  assign n903 = n887[2]; // extract
  /* TG68K_ALU.vhd:591:25  */
  assign n904 = n901 ? n902 : n903;
  /* TG68K_ALU.vhd:591:43  */
  assign n906 = shifted_bitmask[3]; // extract
  /* TG68K_ALU.vhd:592:56  */
  assign n907 = result_tmp[3]; // extract
  assign n908 = n887[3]; // extract
  /* TG68K_ALU.vhd:591:25  */
  assign n909 = n906 ? n907 : n908;
  /* TG68K_ALU.vhd:591:43  */
  assign n911 = shifted_bitmask[4]; // extract
  /* TG68K_ALU.vhd:592:56  */
  assign n912 = result_tmp[4]; // extract
  assign n913 = n887[4]; // extract
  /* TG68K_ALU.vhd:591:25  */
  assign n914 = n911 ? n912 : n913;
  /* TG68K_ALU.vhd:591:43  */
  assign n916 = shifted_bitmask[5]; // extract
  /* TG68K_ALU.vhd:592:56  */
  assign n917 = result_tmp[5]; // extract
  assign n918 = n887[5]; // extract
  /* TG68K_ALU.vhd:591:25  */
  assign n919 = n916 ? n917 : n918;
  /* TG68K_ALU.vhd:591:43  */
  assign n921 = shifted_bitmask[6]; // extract
  /* TG68K_ALU.vhd:592:56  */
  assign n922 = result_tmp[6]; // extract
  assign n923 = n887[6]; // extract
  /* TG68K_ALU.vhd:591:25  */
  assign n924 = n921 ? n922 : n923;
  /* TG68K_ALU.vhd:591:43  */
  assign n926 = shifted_bitmask[7]; // extract
  /* TG68K_ALU.vhd:592:56  */
  assign n927 = result_tmp[7]; // extract
  assign n928 = n887[7]; // extract
  /* TG68K_ALU.vhd:591:25  */
  assign n929 = n926 ? n927 : n928;
  /* TG68K_ALU.vhd:591:43  */
  assign n931 = shifted_bitmask[8]; // extract
  /* TG68K_ALU.vhd:592:56  */
  assign n932 = result_tmp[8]; // extract
  assign n933 = n887[8]; // extract
  /* TG68K_ALU.vhd:591:25  */
  assign n934 = n931 ? n932 : n933;
  /* TG68K_ALU.vhd:591:43  */
  assign n936 = shifted_bitmask[9]; // extract
  /* TG68K_ALU.vhd:592:56  */
  assign n937 = result_tmp[9]; // extract
  assign n938 = n887[9]; // extract
  /* TG68K_ALU.vhd:591:25  */
  assign n939 = n936 ? n937 : n938;
  /* TG68K_ALU.vhd:591:43  */
  assign n941 = shifted_bitmask[10]; // extract
  /* TG68K_ALU.vhd:592:56  */
  assign n942 = result_tmp[10]; // extract
  assign n943 = n887[10]; // extract
  /* TG68K_ALU.vhd:591:25  */
  assign n944 = n941 ? n942 : n943;
  /* TG68K_ALU.vhd:591:43  */
  assign n946 = shifted_bitmask[11]; // extract
  /* TG68K_ALU.vhd:592:56  */
  assign n947 = result_tmp[11]; // extract
  assign n948 = n887[11]; // extract
  /* TG68K_ALU.vhd:591:25  */
  assign n949 = n946 ? n947 : n948;
  /* TG68K_ALU.vhd:591:43  */
  assign n951 = shifted_bitmask[12]; // extract
  /* TG68K_ALU.vhd:592:56  */
  assign n952 = result_tmp[12]; // extract
  assign n953 = n887[12]; // extract
  /* TG68K_ALU.vhd:591:25  */
  assign n954 = n951 ? n952 : n953;
  /* TG68K_ALU.vhd:591:43  */
  assign n956 = shifted_bitmask[13]; // extract
  /* TG68K_ALU.vhd:592:56  */
  assign n957 = result_tmp[13]; // extract
  assign n958 = n887[13]; // extract
  /* TG68K_ALU.vhd:591:25  */
  assign n959 = n956 ? n957 : n958;
  /* TG68K_ALU.vhd:591:43  */
  assign n961 = shifted_bitmask[14]; // extract
  /* TG68K_ALU.vhd:592:56  */
  assign n962 = result_tmp[14]; // extract
  assign n963 = n887[14]; // extract
  /* TG68K_ALU.vhd:591:25  */
  assign n964 = n961 ? n962 : n963;
  /* TG68K_ALU.vhd:591:43  */
  assign n966 = shifted_bitmask[15]; // extract
  /* TG68K_ALU.vhd:592:56  */
  assign n967 = result_tmp[15]; // extract
  assign n968 = n887[15]; // extract
  /* TG68K_ALU.vhd:591:25  */
  assign n969 = n966 ? n967 : n968;
  /* TG68K_ALU.vhd:591:43  */
  assign n971 = shifted_bitmask[16]; // extract
  /* TG68K_ALU.vhd:592:56  */
  assign n972 = result_tmp[16]; // extract
  assign n973 = n887[16]; // extract
  /* TG68K_ALU.vhd:591:25  */
  assign n974 = n971 ? n972 : n973;
  /* TG68K_ALU.vhd:591:43  */
  assign n976 = shifted_bitmask[17]; // extract
  /* TG68K_ALU.vhd:592:56  */
  assign n977 = result_tmp[17]; // extract
  assign n978 = n887[17]; // extract
  /* TG68K_ALU.vhd:591:25  */
  assign n979 = n976 ? n977 : n978;
  /* TG68K_ALU.vhd:591:43  */
  assign n981 = shifted_bitmask[18]; // extract
  /* TG68K_ALU.vhd:592:56  */
  assign n982 = result_tmp[18]; // extract
  assign n983 = n887[18]; // extract
  /* TG68K_ALU.vhd:591:25  */
  assign n984 = n981 ? n982 : n983;
  /* TG68K_ALU.vhd:591:43  */
  assign n986 = shifted_bitmask[19]; // extract
  /* TG68K_ALU.vhd:592:56  */
  assign n987 = result_tmp[19]; // extract
  assign n988 = n887[19]; // extract
  /* TG68K_ALU.vhd:591:25  */
  assign n989 = n986 ? n987 : n988;
  /* TG68K_ALU.vhd:591:43  */
  assign n991 = shifted_bitmask[20]; // extract
  /* TG68K_ALU.vhd:592:56  */
  assign n992 = result_tmp[20]; // extract
  assign n993 = n887[20]; // extract
  /* TG68K_ALU.vhd:591:25  */
  assign n994 = n991 ? n992 : n993;
  /* TG68K_ALU.vhd:591:43  */
  assign n996 = shifted_bitmask[21]; // extract
  /* TG68K_ALU.vhd:592:56  */
  assign n997 = result_tmp[21]; // extract
  assign n998 = n887[21]; // extract
  /* TG68K_ALU.vhd:591:25  */
  assign n999 = n996 ? n997 : n998;
  /* TG68K_ALU.vhd:591:43  */
  assign n1001 = shifted_bitmask[22]; // extract
  /* TG68K_ALU.vhd:592:56  */
  assign n1002 = result_tmp[22]; // extract
  assign n1003 = n887[22]; // extract
  /* TG68K_ALU.vhd:591:25  */
  assign n1004 = n1001 ? n1002 : n1003;
  /* TG68K_ALU.vhd:591:43  */
  assign n1006 = shifted_bitmask[23]; // extract
  /* TG68K_ALU.vhd:592:56  */
  assign n1007 = result_tmp[23]; // extract
  assign n1008 = n887[23]; // extract
  /* TG68K_ALU.vhd:591:25  */
  assign n1009 = n1006 ? n1007 : n1008;
  /* TG68K_ALU.vhd:591:43  */
  assign n1011 = shifted_bitmask[24]; // extract
  /* TG68K_ALU.vhd:592:56  */
  assign n1012 = result_tmp[24]; // extract
  assign n1013 = n887[24]; // extract
  /* TG68K_ALU.vhd:591:25  */
  assign n1014 = n1011 ? n1012 : n1013;
  /* TG68K_ALU.vhd:591:43  */
  assign n1016 = shifted_bitmask[25]; // extract
  /* TG68K_ALU.vhd:592:56  */
  assign n1017 = result_tmp[25]; // extract
  assign n1018 = n887[25]; // extract
  /* TG68K_ALU.vhd:591:25  */
  assign n1019 = n1016 ? n1017 : n1018;
  /* TG68K_ALU.vhd:591:43  */
  assign n1021 = shifted_bitmask[26]; // extract
  /* TG68K_ALU.vhd:592:56  */
  assign n1022 = result_tmp[26]; // extract
  assign n1023 = n887[26]; // extract
  /* TG68K_ALU.vhd:591:25  */
  assign n1024 = n1021 ? n1022 : n1023;
  /* TG68K_ALU.vhd:591:43  */
  assign n1026 = shifted_bitmask[27]; // extract
  /* TG68K_ALU.vhd:592:56  */
  assign n1027 = result_tmp[27]; // extract
  assign n1028 = n887[27]; // extract
  /* TG68K_ALU.vhd:591:25  */
  assign n1029 = n1026 ? n1027 : n1028;
  /* TG68K_ALU.vhd:591:43  */
  assign n1031 = shifted_bitmask[28]; // extract
  /* TG68K_ALU.vhd:592:56  */
  assign n1032 = result_tmp[28]; // extract
  assign n1033 = n887[28]; // extract
  /* TG68K_ALU.vhd:591:25  */
  assign n1034 = n1031 ? n1032 : n1033;
  /* TG68K_ALU.vhd:591:43  */
  assign n1036 = shifted_bitmask[29]; // extract
  /* TG68K_ALU.vhd:592:56  */
  assign n1037 = result_tmp[29]; // extract
  assign n1038 = n887[29]; // extract
  /* TG68K_ALU.vhd:591:25  */
  assign n1039 = n1036 ? n1037 : n1038;
  /* TG68K_ALU.vhd:591:43  */
  assign n1041 = shifted_bitmask[30]; // extract
  /* TG68K_ALU.vhd:592:56  */
  assign n1042 = result_tmp[30]; // extract
  assign n1043 = n887[30]; // extract
  /* TG68K_ALU.vhd:591:25  */
  assign n1044 = n1041 ? n1042 : n1043;
  /* TG68K_ALU.vhd:591:43  */
  assign n1046 = shifted_bitmask[31]; // extract
  /* TG68K_ALU.vhd:592:56  */
  assign n1047 = result_tmp[31]; // extract
  assign n1048 = n887[31]; // extract
  /* TG68K_ALU.vhd:591:25  */
  assign n1049 = n1046 ? n1047 : n1048;
  /* TG68K_ALU.vhd:591:43  */
  assign n1051 = shifted_bitmask[32]; // extract
  /* TG68K_ALU.vhd:592:56  */
  assign n1052 = result_tmp[32]; // extract
  assign n1053 = n887[32]; // extract
  /* TG68K_ALU.vhd:591:25  */
  assign n1054 = n1051 ? n1052 : n1053;
  /* TG68K_ALU.vhd:591:43  */
  assign n1056 = shifted_bitmask[33]; // extract
  /* TG68K_ALU.vhd:592:56  */
  assign n1057 = result_tmp[33]; // extract
  assign n1058 = n887[33]; // extract
  /* TG68K_ALU.vhd:591:25  */
  assign n1059 = n1056 ? n1057 : n1058;
  /* TG68K_ALU.vhd:591:43  */
  assign n1061 = shifted_bitmask[34]; // extract
  /* TG68K_ALU.vhd:592:56  */
  assign n1062 = result_tmp[34]; // extract
  assign n1063 = n887[34]; // extract
  /* TG68K_ALU.vhd:591:25  */
  assign n1064 = n1061 ? n1062 : n1063;
  /* TG68K_ALU.vhd:591:43  */
  assign n1066 = shifted_bitmask[35]; // extract
  /* TG68K_ALU.vhd:592:56  */
  assign n1067 = result_tmp[35]; // extract
  assign n1068 = n887[35]; // extract
  /* TG68K_ALU.vhd:591:25  */
  assign n1069 = n1066 ? n1067 : n1068;
  /* TG68K_ALU.vhd:591:43  */
  assign n1071 = shifted_bitmask[36]; // extract
  /* TG68K_ALU.vhd:592:56  */
  assign n1072 = result_tmp[36]; // extract
  assign n1073 = n887[36]; // extract
  /* TG68K_ALU.vhd:591:25  */
  assign n1074 = n1071 ? n1072 : n1073;
  /* TG68K_ALU.vhd:591:43  */
  assign n1076 = shifted_bitmask[37]; // extract
  /* TG68K_ALU.vhd:592:56  */
  assign n1077 = result_tmp[37]; // extract
  assign n1078 = n887[37]; // extract
  /* TG68K_ALU.vhd:591:25  */
  assign n1079 = n1076 ? n1077 : n1078;
  /* TG68K_ALU.vhd:591:43  */
  assign n1081 = shifted_bitmask[38]; // extract
  /* TG68K_ALU.vhd:592:56  */
  assign n1082 = result_tmp[38]; // extract
  assign n1083 = n887[38]; // extract
  /* TG68K_ALU.vhd:591:25  */
  assign n1084 = n1081 ? n1082 : n1083;
  assign n1085 = n887[39]; // extract
  /* TG68K_ALU.vhd:591:43  */
  assign n1086 = shifted_bitmask[39]; // extract
  /* TG68K_ALU.vhd:592:56  */
  assign n1087 = result_tmp[39]; // extract
  /* TG68K_ALU.vhd:591:25  */
  assign n1088 = n1086 ? n1087 : n1085;
  /* TG68K_ALU.vhd:598:36  */
  assign n1090 = {1'b0, bitnr};
  /* TG68K_ALU.vhd:598:43  */
  assign n1091 = {5'b0, mask_not_zero};  //  uext
  /* TG68K_ALU.vhd:598:43  */
  assign n1092 = n1090 + n1091;
  /* TG68K_ALU.vhd:601:24  */
  assign n1093 = mask[31:28]; // extract
  /* TG68K_ALU.vhd:601:38  */
  assign n1095 = n1093 == 4'b0000;
  /* TG68K_ALU.vhd:602:32  */
  assign n1096 = mask[27:24]; // extract
  /* TG68K_ALU.vhd:602:46  */
  assign n1098 = n1096 == 4'b0000;
  /* TG68K_ALU.vhd:603:40  */
  assign n1099 = mask[23:20]; // extract
  /* TG68K_ALU.vhd:603:54  */
  assign n1101 = n1099 == 4'b0000;
  /* TG68K_ALU.vhd:604:48  */
  assign n1102 = mask[19:16]; // extract
  /* TG68K_ALU.vhd:604:62  */
  assign n1104 = n1102 == 4'b0000;
  /* TG68K_ALU.vhd:606:56  */
  assign n1106 = mask[15:12]; // extract
  /* TG68K_ALU.vhd:606:70  */
  assign n1108 = n1106 == 4'b0000;
  /* TG68K_ALU.vhd:607:64  */
  assign n1109 = mask[11:8]; // extract
  /* TG68K_ALU.vhd:607:77  */
  assign n1111 = n1109 == 4'b0000;
  /* TG68K_ALU.vhd:609:72  */
  assign n1113 = mask[7:4]; // extract
  /* TG68K_ALU.vhd:609:84  */
  assign n1115 = n1113 == 4'b0000;
  /* TG68K_ALU.vhd:611:84  */
  assign n1117 = mask[3:0]; // extract
  /* TG68K_ALU.vhd:613:84  */
  assign n1118 = mask[7:4]; // extract
  /* TG68K_ALU.vhd:609:65  */
  assign n1119 = n1115 ? n1117 : n1118;
  /* TG68K_ALU.vhd:609:65  */
  assign n1121 = n1115 ? 1'b0 : 1'b1;
  /* TG68K_ALU.vhd:616:76  */
  assign n1122 = mask[11:8]; // extract
  /* TG68K_ALU.vhd:607:57  */
  assign n1124 = n1111 ? n1119 : n1122;
  assign n1125 = {1'b0, n1121};
  assign n1126 = n1125[0]; // extract
  /* TG68K_ALU.vhd:607:57  */
  assign n1127 = n1111 ? n1126 : 1'b0;
  assign n1128 = n1125[1]; // extract
  /* TG68K_ALU.vhd:607:57  */
  assign n1130 = n1111 ? n1128 : 1'b1;
  /* TG68K_ALU.vhd:620:68  */
  assign n1131 = mask[15:12]; // extract
  /* TG68K_ALU.vhd:606:49  */
  assign n1132 = n1108 ? n1124 : n1131;
  assign n1133 = {n1130, n1127};
  /* TG68K_ALU.vhd:606:49  */
  assign n1135 = n1108 ? n1133 : 2'b11;
  /* TG68K_ALU.vhd:623:60  */
  assign n1136 = mask[19:16]; // extract
  /* TG68K_ALU.vhd:604:41  */
  assign n1139 = n1104 ? n1132 : n1136;
  assign n1140 = {1'b0, 1'b0};
  assign n1141 = {1'b0, n1135};
  assign n1142 = n1141[1:0]; // extract
  /* TG68K_ALU.vhd:604:41  */
  assign n1143 = n1104 ? n1142 : n1140;
  assign n1144 = n1141[2]; // extract
  /* TG68K_ALU.vhd:604:41  */
  assign n1146 = n1104 ? n1144 : 1'b1;
  /* TG68K_ALU.vhd:628:52  */
  assign n1147 = mask[23:20]; // extract
  /* TG68K_ALU.vhd:603:33  */
  assign n1149 = n1101 ? n1139 : n1147;
  assign n1150 = {n1146, n1143};
  assign n1151 = n1150[0]; // extract
  /* TG68K_ALU.vhd:603:33  */
  assign n1153 = n1101 ? n1151 : 1'b1;
  assign n1154 = n1150[1]; // extract
  /* TG68K_ALU.vhd:603:33  */
  assign n1155 = n1101 ? n1154 : 1'b0;
  assign n1156 = n1150[2]; // extract
  /* TG68K_ALU.vhd:603:33  */
  assign n1158 = n1101 ? n1156 : 1'b1;
  /* TG68K_ALU.vhd:632:44  */
  assign n1159 = mask[27:24]; // extract
  /* TG68K_ALU.vhd:602:25  */
  assign n1161 = n1098 ? n1149 : n1159;
  assign n1162 = {n1158, n1155, n1153};
  assign n1163 = n1162[0]; // extract
  /* TG68K_ALU.vhd:602:25  */
  assign n1164 = n1098 ? n1163 : 1'b0;
  assign n1165 = n1162[2:1]; // extract
  /* TG68K_ALU.vhd:602:25  */
  assign n1167 = n1098 ? n1165 : 2'b11;
  /* TG68K_ALU.vhd:636:36  */
  assign n1168 = mask[31:28]; // extract
  /* TG68K_ALU.vhd:601:17  */
  assign n1169 = n1095 ? n1161 : n1168;
  assign n1170 = {n1167, n1164};
  /* TG68K_ALU.vhd:601:17  */
  assign n1172 = n1095 ? n1170 : 3'b111;
  /* TG68K_ALU.vhd:639:23  */
  assign n1175 = mux[3:2]; // extract
  /* TG68K_ALU.vhd:639:35  */
  assign n1177 = n1175 == 2'b00;
  /* TG68K_ALU.vhd:641:31  */
  assign n1179 = mux[1]; // extract
  /* TG68K_ALU.vhd:641:34  */
  assign n1180 = ~n1179;
  /* TG68K_ALU.vhd:643:39  */
  assign n1182 = mux[0]; // extract
  /* TG68K_ALU.vhd:643:42  */
  assign n1183 = ~n1182;
  /* TG68K_ALU.vhd:643:33  */
  assign n1186 = n1183 ? 1'b0 : 1'b1;
  assign n1187 = n1173[0]; // extract
  /* TG68K_ALU.vhd:641:25  */
  assign n1188 = n1180 ? 1'b0 : n1187;
  /* TG68K_ALU.vhd:641:25  */
  assign n1190 = n1180 ? n1186 : 1'b1;
  /* TG68K_ALU.vhd:648:31  */
  assign n1191 = mux[3]; // extract
  /* TG68K_ALU.vhd:648:34  */
  assign n1192 = ~n1191;
  assign n1194 = n1173[0]; // extract
  /* TG68K_ALU.vhd:648:25  */
  assign n1195 = n1192 ? 1'b0 : n1194;
  assign n1196 = {1'b0, n1188};
  assign n1197 = n1196[0]; // extract
  /* TG68K_ALU.vhd:639:17  */
  assign n1198 = n1177 ? n1197 : n1195;
  assign n1199 = n1196[1]; // extract
  assign n1200 = n1173[1]; // extract
  /* TG68K_ALU.vhd:639:17  */
  assign n1201 = n1177 ? n1199 : n1200;
  /* TG68K_ALU.vhd:639:17  */
  assign n1204 = n1177 ? n1190 : 1'b1;
  /* TG68K_ALU.vhd:659:32  */
  assign n1209 = exe_opcode[7:6]; // extract
  /* TG68K_ALU.vhd:661:66  */
  assign n1210 = OP1out[7]; // extract
  /* TG68K_ALU.vhd:660:25  */
  assign n1212 = n1209 == 2'b00;
  /* TG68K_ALU.vhd:663:66  */
  assign n1213 = OP1out[15]; // extract
  /* TG68K_ALU.vhd:662:25  */
  assign n1215 = n1209 == 2'b01;
  /* TG68K_ALU.vhd:662:34  */
  assign n1217 = n1209 == 2'b11;
  /* TG68K_ALU.vhd:662:34  */
  assign n1218 = n1215 | n1217;
  /* TG68K_ALU.vhd:665:66  */
  assign n1219 = OP1out[31]; // extract
  /* TG68K_ALU.vhd:664:25  */
  assign n1221 = n1209 == 2'b10;
  assign n1222 = {n1221, n1218, n1212};
  /* TG68K_ALU.vhd:659:17  */
  always @*
    case (n1222)
      3'b100: n1223 = n1219;
      3'b010: n1223 = n1213;
      3'b001: n1223 = n1210;
      default: n1223 = rot_rot;
    endcase
  /* TG68K_ALU.vhd:685:24  */
  assign n1241 = exec[23]; // extract
  /* TG68K_ALU.vhd:687:39  */
  assign n1242 = n2364[4]; // extract
  /* TG68K_ALU.vhd:688:36  */
  assign n1244 = rot_bits == 2'b10;
  /* TG68K_ALU.vhd:689:47  */
  assign n1245 = n2364[4]; // extract
  /* TG68K_ALU.vhd:688:25  */
  assign n1247 = n1244 ? n1245 : 1'b0;
  /* TG68K_ALU.vhd:694:38  */
  assign n1248 = exe_opcode[8]; // extract
  /* TG68K_ALU.vhd:699:48  */
  assign n1251 = OP1out[0]; // extract
  /* TG68K_ALU.vhd:700:48  */
  assign n1252 = OP1out[0]; // extract
  /* TG68K_ALU.vhd:694:25  */
  assign n1272 = n1248 ? rot_rot : n1251;
  /* TG68K_ALU.vhd:694:25  */
  assign n1273 = n1248 ? rot_rot : n1252;
  /* TG68K_ALU.vhd:685:17  */
  assign n1276 = n1241 ? n1242 : n1272;
  /* TG68K_ALU.vhd:685:17  */
  assign n1277 = n1241 ? n1247 : n1273;
  /* TG68K_ALU.vhd:685:17  */
  assign n1278 = n1241 ? OP1out : bsout;
  /* TG68K_ALU.vhd:723:28  */
  assign n1283 = rot_bits == 2'b10;
  /* TG68K_ALU.vhd:724:40  */
  assign n1284 = exe_opcode[7:6]; // extract
  /* TG68K_ALU.vhd:725:33  */
  assign n1286 = n1284 == 2'b00;
  /* TG68K_ALU.vhd:727:33  */
  assign n1288 = n1284 == 2'b01;
  /* TG68K_ALU.vhd:727:42  */
  assign n1290 = n1284 == 2'b11;
  /* TG68K_ALU.vhd:727:42  */
  assign n1291 = n1288 | n1290;
  /* TG68K_ALU.vhd:729:33  */
  assign n1293 = n1284 == 2'b10;
  assign n1294 = {n1293, n1291, n1286};
  /* TG68K_ALU.vhd:724:25  */
  always @*
    case (n1294)
      3'b100: n1299 = 6'b100001;
      3'b010: n1299 = 6'b010001;
      3'b001: n1299 = 6'b001001;
      default: n1299 = 6'b100000;
    endcase
  /* TG68K_ALU.vhd:734:40  */
  assign n1300 = exe_opcode[7:6]; // extract
  /* TG68K_ALU.vhd:735:33  */
  assign n1302 = n1300 == 2'b00;
  /* TG68K_ALU.vhd:737:33  */
  assign n1304 = n1300 == 2'b01;
  /* TG68K_ALU.vhd:737:42  */
  assign n1306 = n1300 == 2'b11;
  /* TG68K_ALU.vhd:737:42  */
  assign n1307 = n1304 | n1306;
  /* TG68K_ALU.vhd:739:33  */
  assign n1309 = n1300 == 2'b10;
  assign n1310 = {n1309, n1307, n1302};
  /* TG68K_ALU.vhd:734:25  */
  always @*
    case (n1310)
      3'b100: n1315 = 6'b100000;
      3'b010: n1315 = 6'b010000;
      3'b001: n1315 = 6'b001000;
      default: n1315 = 6'b100000;
    endcase
  /* TG68K_ALU.vhd:723:17  */
  assign n1316 = n1283 ? n1299 : n1315;
  /* TG68K_ALU.vhd:745:30  */
  assign n1318 = exe_opcode[7:6]; // extract
  /* TG68K_ALU.vhd:745:42  */
  assign n1320 = n1318 == 2'b11;
  /* TG68K_ALU.vhd:745:55  */
  assign n1321 = exec[81]; // extract
  /* TG68K_ALU.vhd:745:64  */
  assign n1322 = ~n1321;
  /* TG68K_ALU.vhd:745:48  */
  assign n1323 = n1320 | n1322;
  /* TG68K_ALU.vhd:747:33  */
  assign n1324 = exe_opcode[5]; // extract
  /* TG68K_ALU.vhd:748:43  */
  assign n1325 = OP2out[5:0]; // extract
  /* TG68K_ALU.vhd:750:59  */
  assign n1326 = exe_opcode[11:9]; // extract
  /* TG68K_ALU.vhd:751:38  */
  assign n1327 = exe_opcode[11:9]; // extract
  /* TG68K_ALU.vhd:751:51  */
  assign n1329 = n1327 == 3'b000;
  /* TG68K_ALU.vhd:751:25  */
  assign n1332 = n1329 ? 3'b001 : 3'b000;
  assign n1333 = {n1332, n1326};
  /* TG68K_ALU.vhd:747:17  */
  assign n1334 = n1324 ? n1325 : n1333;
  /* TG68K_ALU.vhd:745:17  */
  assign n1336 = n1323 ? 6'b000001 : n1334;
  /* TG68K_ALU.vhd:762:29  */
  assign n1343 = $unsigned(bs_shift) < $unsigned(ring);
  /* TG68K_ALU.vhd:763:40  */
  assign n1344 = ring - bs_shift;
  /* TG68K_ALU.vhd:762:17  */
  assign n1346 = n1343 ? n1344 : 6'b000000;
  /* TG68K_ALU.vhd:765:45  */
  assign n1348 = vector[30:0]; // extract
  /* TG68K_ALU.vhd:765:38  */
  assign n1350 = {1'b0, n1348};
  /* TG68K_ALU.vhd:765:75  */
  assign n1351 = vector[31:1]; // extract
  /* TG68K_ALU.vhd:765:68  */
  assign n1353 = {1'b0, n1351};
  /* TG68K_ALU.vhd:765:60  */
  assign n1354 = n1350 ^ n1353;
  /* TG68K_ALU.vhd:765:90  */
  assign n1355 = {n1354, msb};
  /* TG68K_ALU.vhd:766:32  */
  assign n1356 = exe_opcode[7:6]; // extract
  /* TG68K_ALU.vhd:767:25  */
  assign n1359 = n1356 == 2'b00;
  /* TG68K_ALU.vhd:769:25  */
  assign n1362 = n1356 == 2'b01;
  /* TG68K_ALU.vhd:769:34  */
  assign n1364 = n1356 == 2'b11;
  /* TG68K_ALU.vhd:769:34  */
  assign n1365 = n1362 | n1364;
  assign n1366 = {n1365, n1359};
  assign n1367 = n1355[8]; // extract
  /* TG68K_ALU.vhd:766:17  */
  always @*
    case (n1366)
      2'b10: n1368 = n1367;
      2'b01: n1368 = 1'b0;
      default: n1368 = n1367;
    endcase
  assign n1369 = n1355[16]; // extract
  /* TG68K_ALU.vhd:766:17  */
  always @*
    case (n1366)
      2'b10: n1370 = 1'b0;
      2'b01: n1370 = n1369;
      default: n1370 = n1369;
    endcase
  assign n1372 = n1355[7:0]; // extract
  assign n1373 = n1355[32:17]; // extract
  assign n1374 = n1355[15:9]; // extract
  /* TG68K_ALU.vhd:773:56  */
  assign n1375 = hot_msb[31:0]; // extract
  /* TG68K_ALU.vhd:773:48  */
  assign n1377 = {1'b0, n1375};
  /* TG68K_ALU.vhd:773:42  */
  assign n1378 = asl_over_xor - n1377;
  /* TG68K_ALU.vhd:775:28  */
  assign n1380 = rot_bits == 2'b00;
  /* TG68K_ALU.vhd:775:48  */
  assign n1381 = exe_opcode[8]; // extract
  /* TG68K_ALU.vhd:775:34  */
  assign n1382 = n1381 & n1380;
  /* TG68K_ALU.vhd:776:45  */
  assign n1383 = asl_over[32]; // extract
  /* TG68K_ALU.vhd:776:33  */
  assign n1384 = ~n1383;
  /* TG68K_ALU.vhd:775:17  */
  assign n1386 = n1382 ? n1384 : 1'b0;
  /* TG68K_ALU.vhd:780:30  */
  assign n1388 = exe_opcode[8]; // extract
  /* TG68K_ALU.vhd:780:33  */
  assign n1389 = ~n1388;
  /* TG68K_ALU.vhd:781:42  */
  assign n1390 = result_bs[31]; // extract
  /* TG68K_ALU.vhd:783:40  */
  assign n1391 = exe_opcode[7:6]; // extract
  /* TG68K_ALU.vhd:785:58  */
  assign n1392 = result_bs[8]; // extract
  /* TG68K_ALU.vhd:784:33  */
  assign n1394 = n1391 == 2'b00;
  /* TG68K_ALU.vhd:787:58  */
  assign n1395 = result_bs[16]; // extract
  /* TG68K_ALU.vhd:786:33  */
  assign n1397 = n1391 == 2'b01;
  /* TG68K_ALU.vhd:786:42  */
  assign n1399 = n1391 == 2'b11;
  /* TG68K_ALU.vhd:786:42  */
  assign n1400 = n1397 | n1399;
  /* TG68K_ALU.vhd:789:58  */
  assign n1401 = result_bs[32]; // extract
  /* TG68K_ALU.vhd:788:33  */
  assign n1403 = n1391 == 2'b10;
  assign n1404 = {n1403, n1400, n1394};
  /* TG68K_ALU.vhd:783:25  */
  always @*
    case (n1404)
      3'b100: n1405 = n1401;
      3'b010: n1405 = n1395;
      3'b001: n1405 = n1392;
      default: n1405 = bs_c;
    endcase
  /* TG68K_ALU.vhd:780:17  */
  assign n1406 = n1389 ? n1390 : n1405;
  /* TG68K_ALU.vhd:795:28  */
  assign n1408 = rot_bits == 2'b11;
  /* TG68K_ALU.vhd:796:38  */
  assign n1409 = n2364[4]; // extract
  /* TG68K_ALU.vhd:797:40  */
  assign n1410 = exe_opcode[7:6]; // extract
  /* TG68K_ALU.vhd:799:69  */
  assign n1411 = result_bs[7:0]; // extract
  /* TG68K_ALU.vhd:799:94  */
  assign n1412 = result_bs[15:8]; // extract
  /* TG68K_ALU.vhd:799:82  */
  assign n1413 = n1411 | n1412;
  /* TG68K_ALU.vhd:800:52  */
  assign n1414 = alu[7]; // extract
  /* TG68K_ALU.vhd:798:33  */
  assign n1416 = n1410 == 2'b00;
  /* TG68K_ALU.vhd:802:70  */
  assign n1417 = result_bs[15:0]; // extract
  /* TG68K_ALU.vhd:802:96  */
  assign n1418 = result_bs[31:16]; // extract
  /* TG68K_ALU.vhd:802:84  */
  assign n1419 = n1417 | n1418;
  /* TG68K_ALU.vhd:803:52  */
  assign n1420 = alu[15]; // extract
  /* TG68K_ALU.vhd:801:33  */
  assign n1422 = n1410 == 2'b01;
  /* TG68K_ALU.vhd:801:42  */
  assign n1424 = n1410 == 2'b11;
  /* TG68K_ALU.vhd:801:42  */
  assign n1425 = n1422 | n1424;
  /* TG68K_ALU.vhd:805:57  */
  assign n1426 = result_bs[31:0]; // extract
  /* TG68K_ALU.vhd:805:83  */
  assign n1427 = result_bs[63:32]; // extract
  /* TG68K_ALU.vhd:805:71  */
  assign n1428 = n1426 | n1427;
  /* TG68K_ALU.vhd:806:52  */
  assign n1429 = alu[31]; // extract
  /* TG68K_ALU.vhd:804:33  */
  assign n1431 = n1410 == 2'b10;
  assign n1432 = {n1431, n1425, n1416};
  assign n1433 = n1419[7:0]; // extract
  assign n1434 = n1428[7:0]; // extract
  /* TG68K_ALU.vhd:797:25  */
  always @*
    case (n1432)
      3'b100: n1436 = n1434;
      3'b010: n1436 = n1433;
      3'b001: n1436 = n1413;
      default: n1436 = 8'bX;
    endcase
  assign n1437 = n1419[15:8]; // extract
  assign n1438 = n1428[15:8]; // extract
  /* TG68K_ALU.vhd:797:25  */
  always @*
    case (n1432)
      3'b100: n1440 = n1438;
      3'b010: n1440 = n1437;
      3'b001: n1440 = 8'bX;
      default: n1440 = 8'bX;
    endcase
  assign n1441 = n1428[31:16]; // extract
  /* TG68K_ALU.vhd:797:25  */
  always @*
    case (n1432)
      3'b100: n1443 = n1441;
      3'b010: n1443 = 16'bX;
      3'b001: n1443 = 16'bX;
      default: n1443 = 16'bX;
    endcase
  /* TG68K_ALU.vhd:797:25  */
  always @*
    case (n1432)
      3'b100: n1444 = n1429;
      3'b010: n1444 = n1420;
      3'b001: n1444 = n1414;
      default: n1444 = n1406;
    endcase
  /* TG68K_ALU.vhd:809:38  */
  assign n1445 = exe_opcode[8]; // extract
  /* TG68K_ALU.vhd:810:44  */
  assign n1446 = alu[0]; // extract
  /* TG68K_ALU.vhd:809:25  */
  assign n1447 = n1445 ? n1446 : n1444;
  /* TG68K_ALU.vhd:812:31  */
  assign n1449 = rot_bits == 2'b10;
  /* TG68K_ALU.vhd:813:40  */
  assign n1450 = exe_opcode[7:6]; // extract
  /* TG68K_ALU.vhd:815:69  */
  assign n1451 = result_bs[7:0]; // extract
  /* TG68K_ALU.vhd:815:94  */
  assign n1452 = result_bs[16:9]; // extract
  /* TG68K_ALU.vhd:815:82  */
  assign n1453 = n1451 | n1452;
  /* TG68K_ALU.vhd:816:58  */
  assign n1454 = result_bs[8]; // extract
  /* TG68K_ALU.vhd:816:74  */
  assign n1455 = result_bs[17]; // extract
  /* TG68K_ALU.vhd:816:62  */
  assign n1456 = n1454 | n1455;
  /* TG68K_ALU.vhd:814:33  */
  assign n1458 = n1450 == 2'b00;
  /* TG68K_ALU.vhd:818:70  */
  assign n1459 = result_bs[15:0]; // extract
  /* TG68K_ALU.vhd:818:96  */
  assign n1460 = result_bs[32:17]; // extract
  /* TG68K_ALU.vhd:818:84  */
  assign n1461 = n1459 | n1460;
  /* TG68K_ALU.vhd:819:58  */
  assign n1462 = result_bs[16]; // extract
  /* TG68K_ALU.vhd:819:75  */
  assign n1463 = result_bs[33]; // extract
  /* TG68K_ALU.vhd:819:63  */
  assign n1464 = n1462 | n1463;
  /* TG68K_ALU.vhd:817:33  */
  assign n1466 = n1450 == 2'b01;
  /* TG68K_ALU.vhd:817:42  */
  assign n1468 = n1450 == 2'b11;
  /* TG68K_ALU.vhd:817:42  */
  assign n1469 = n1466 | n1468;
  /* TG68K_ALU.vhd:821:57  */
  assign n1470 = result_bs[31:0]; // extract
  /* TG68K_ALU.vhd:821:83  */
  assign n1471 = result_bs[64:33]; // extract
  /* TG68K_ALU.vhd:821:71  */
  assign n1472 = n1470 | n1471;
  /* TG68K_ALU.vhd:822:58  */
  assign n1473 = result_bs[32]; // extract
  /* TG68K_ALU.vhd:822:75  */
  assign n1474 = result_bs[65]; // extract
  /* TG68K_ALU.vhd:822:63  */
  assign n1475 = n1473 | n1474;
  /* TG68K_ALU.vhd:820:33  */
  assign n1477 = n1450 == 2'b10;
  assign n1478 = {n1477, n1469, n1458};
  assign n1479 = n1461[7:0]; // extract
  assign n1480 = n1472[7:0]; // extract
  /* TG68K_ALU.vhd:813:25  */
  always @*
    case (n1478)
      3'b100: n1482 = n1480;
      3'b010: n1482 = n1479;
      3'b001: n1482 = n1453;
      default: n1482 = 8'bX;
    endcase
  assign n1483 = n1461[15:8]; // extract
  assign n1484 = n1472[15:8]; // extract
  /* TG68K_ALU.vhd:813:25  */
  always @*
    case (n1478)
      3'b100: n1486 = n1484;
      3'b010: n1486 = n1483;
      3'b001: n1486 = 8'bX;
      default: n1486 = 8'bX;
    endcase
  assign n1487 = n1472[31:16]; // extract
  /* TG68K_ALU.vhd:813:25  */
  always @*
    case (n1478)
      3'b100: n1489 = n1487;
      3'b010: n1489 = 16'bX;
      3'b001: n1489 = 16'bX;
      default: n1489 = 16'bX;
    endcase
  /* TG68K_ALU.vhd:813:25  */
  always @*
    case (n1478)
      3'b100: n1490 = n1475;
      3'b010: n1490 = n1464;
      3'b001: n1490 = n1456;
      default: n1490 = n1406;
    endcase
  /* TG68K_ALU.vhd:826:38  */
  assign n1491 = exe_opcode[8]; // extract
  /* TG68K_ALU.vhd:826:41  */
  assign n1492 = ~n1491;
  /* TG68K_ALU.vhd:827:49  */
  assign n1493 = result_bs[63:32]; // extract
  /* TG68K_ALU.vhd:829:49  */
  assign n1494 = result_bs[31:0]; // extract
  /* TG68K_ALU.vhd:826:25  */
  assign n1495 = n1492 ? n1493 : n1494;
  assign n1496 = {n1489, n1486, n1482};
  /* TG68K_ALU.vhd:812:17  */
  assign n1497 = n1449 ? n1496 : n1495;
  /* TG68K_ALU.vhd:812:17  */
  assign n1498 = n1449 ? n1490 : n1406;
  assign n1499 = {n1443, n1440, n1436};
  /* TG68K_ALU.vhd:795:17  */
  assign n1500 = n1408 ? n1499 : n1497;
  /* TG68K_ALU.vhd:795:17  */
  assign n1502 = n1408 ? n1447 : n1498;
  /* TG68K_ALU.vhd:795:17  */
  assign n1503 = n1408 ? n1409 : bs_c;
  /* TG68K_ALU.vhd:833:29  */
  assign n1505 = bs_shift == 6'b000000;
  /* TG68K_ALU.vhd:834:36  */
  assign n1507 = rot_bits == 2'b10;
  /* TG68K_ALU.vhd:835:46  */
  assign n1508 = n2364[4]; // extract
  /* TG68K_ALU.vhd:834:25  */
  assign n1510 = n1507 ? n1508 : 1'b0;
  /* TG68K_ALU.vhd:839:38  */
  assign n1511 = n2364[4]; // extract
  /* TG68K_ALU.vhd:833:17  */
  assign n1513 = n1505 ? 1'b0 : n1386;
  /* TG68K_ALU.vhd:833:17  */
  assign n1514 = n1505 ? n1510 : n1502;
  /* TG68K_ALU.vhd:833:17  */
  assign n1515 = n1505 ? n1511 : n1503;
  /* TG68K_ALU.vhd:848:45  */
  assign n1517 = bs_shift == 6'b111111;
  /* TG68K_ALU.vhd:850:48  */
  assign n1519 = $unsigned(bs_shift) > $unsigned(6'b110101);
  /* TG68K_ALU.vhd:851:66  */
  assign n1521 = bs_shift - 6'b110110;
  /* TG68K_ALU.vhd:852:48  */
  assign n1523 = $unsigned(bs_shift) > $unsigned(6'b101100);
  /* TG68K_ALU.vhd:853:66  */
  assign n1525 = bs_shift - 6'b101101;
  /* TG68K_ALU.vhd:854:48  */
  assign n1527 = $unsigned(bs_shift) > $unsigned(6'b100011);
  /* TG68K_ALU.vhd:855:66  */
  assign n1529 = bs_shift - 6'b100100;
  /* TG68K_ALU.vhd:856:48  */
  assign n1531 = $unsigned(bs_shift) > $unsigned(6'b011010);
  /* TG68K_ALU.vhd:857:66  */
  assign n1533 = bs_shift - 6'b011011;
  /* TG68K_ALU.vhd:858:48  */
  assign n1535 = $unsigned(bs_shift) > $unsigned(6'b010001);
  /* TG68K_ALU.vhd:859:66  */
  assign n1537 = bs_shift - 6'b010010;
  /* TG68K_ALU.vhd:860:48  */
  assign n1539 = $unsigned(bs_shift) > $unsigned(6'b001000);
  /* TG68K_ALU.vhd:861:66  */
  assign n1541 = bs_shift - 6'b001001;
  /* TG68K_ALU.vhd:860:33  */
  assign n1542 = n1539 ? n1541 : bs_shift;
  /* TG68K_ALU.vhd:858:33  */
  assign n1543 = n1535 ? n1537 : n1542;
  /* TG68K_ALU.vhd:856:33  */
  assign n1544 = n1531 ? n1533 : n1543;
  /* TG68K_ALU.vhd:854:33  */
  assign n1545 = n1527 ? n1529 : n1544;
  /* TG68K_ALU.vhd:852:33  */
  assign n1546 = n1523 ? n1525 : n1545;
  /* TG68K_ALU.vhd:850:33  */
  assign n1547 = n1519 ? n1521 : n1546;
  /* TG68K_ALU.vhd:848:33  */
  assign n1549 = n1517 ? 6'b000000 : n1547;
  /* TG68K_ALU.vhd:847:25  */
  assign n1551 = ring == 6'b001001;
  /* TG68K_ALU.vhd:866:45  */
  assign n1553 = $unsigned(bs_shift) > $unsigned(6'b110010);
  /* TG68K_ALU.vhd:867:66  */
  assign n1555 = bs_shift - 6'b110011;
  /* TG68K_ALU.vhd:868:48  */
  assign n1557 = $unsigned(bs_shift) > $unsigned(6'b100001);
  /* TG68K_ALU.vhd:869:66  */
  assign n1559 = bs_shift - 6'b100010;
  /* TG68K_ALU.vhd:870:48  */
  assign n1561 = $unsigned(bs_shift) > $unsigned(6'b010000);
  /* TG68K_ALU.vhd:871:66  */
  assign n1563 = bs_shift - 6'b010001;
  /* TG68K_ALU.vhd:870:33  */
  assign n1564 = n1561 ? n1563 : bs_shift;
  /* TG68K_ALU.vhd:868:33  */
  assign n1565 = n1557 ? n1559 : n1564;
  /* TG68K_ALU.vhd:866:33  */
  assign n1566 = n1553 ? n1555 : n1565;
  /* TG68K_ALU.vhd:865:25  */
  assign n1568 = ring == 6'b010001;
  /* TG68K_ALU.vhd:876:45  */
  assign n1570 = $unsigned(bs_shift) > $unsigned(6'b100000);
  /* TG68K_ALU.vhd:877:66  */
  assign n1572 = bs_shift - 6'b100001;
  /* TG68K_ALU.vhd:876:33  */
  assign n1573 = n1570 ? n1572 : bs_shift;
  /* TG68K_ALU.vhd:875:25  */
  assign n1575 = ring == 6'b100001;
  /* TG68K_ALU.vhd:881:74  */
  assign n1576 = bs_shift[2:0]; // extract
  /* TG68K_ALU.vhd:881:64  */
  assign n1578 = {3'b000, n1576};
  /* TG68K_ALU.vhd:881:25  */
  assign n1580 = ring == 6'b001000;
  /* TG68K_ALU.vhd:882:74  */
  assign n1581 = bs_shift[3:0]; // extract
  /* TG68K_ALU.vhd:882:64  */
  assign n1583 = {2'b00, n1581};
  /* TG68K_ALU.vhd:882:25  */
  assign n1585 = ring == 6'b010000;
  /* TG68K_ALU.vhd:883:74  */
  assign n1586 = bs_shift[4:0]; // extract
  /* TG68K_ALU.vhd:883:64  */
  assign n1588 = {1'b0, n1586};
  /* TG68K_ALU.vhd:883:25  */
  assign n1590 = ring == 6'b100000;
  assign n1591 = {n1590, n1585, n1580, n1575, n1568, n1551};
  /* TG68K_ALU.vhd:846:17  */
  always @*
    case (n1591)
      6'b100000: n1593 = n1588;
      6'b010000: n1593 = n1583;
      6'b001000: n1593 = n1578;
      6'b000100: n1593 = n1573;
      6'b000010: n1593 = n1566;
      6'b000001: n1593 = n1549;
      default: n1593 = 6'b000000;
    endcase
  /* TG68K_ALU.vhd:888:30  */
  assign n1594 = exe_opcode[8]; // extract
  /* TG68K_ALU.vhd:888:33  */
  assign n1595 = ~n1594;
  /* TG68K_ALU.vhd:889:39  */
  assign n1596 = ring - bs_shift_mod;
  /* TG68K_ALU.vhd:888:17  */
  assign n1597 = n1595 ? n1596 : bs_shift_mod;
  /* TG68K_ALU.vhd:891:28  */
  assign n1598 = rot_bits[1]; // extract
  /* TG68K_ALU.vhd:891:31  */
  assign n1599 = ~n1598;
  /* TG68K_ALU.vhd:892:38  */
  assign n1600 = exe_opcode[8]; // extract
  /* TG68K_ALU.vhd:892:41  */
  assign n1601 = ~n1600;
  /* TG68K_ALU.vhd:893:45  */
  assign n1603 = 6'b100000 - bs_shift_mod;
  /* TG68K_ALU.vhd:892:25  */
  assign n1604 = n1601 ? n1603 : n1597;
  /* TG68K_ALU.vhd:895:37  */
  assign n1605 = bs_shift == ring;
  /* TG68K_ALU.vhd:896:46  */
  assign n1606 = exe_opcode[8]; // extract
  /* TG68K_ALU.vhd:896:49  */
  assign n1607 = ~n1606;
  /* TG68K_ALU.vhd:897:53  */
  assign n1609 = 6'b100000 - ring;
  /* TG68K_ALU.vhd:896:33  */
  assign n1610 = n1607 ? n1609 : ring;
  /* TG68K_ALU.vhd:895:25  */
  assign n1611 = n1605 ? n1610 : n1604;
  /* TG68K_ALU.vhd:902:37  */
  assign n1612 = $unsigned(bs_shift) > $unsigned(ring);
  /* TG68K_ALU.vhd:903:46  */
  assign n1613 = exe_opcode[8]; // extract
  /* TG68K_ALU.vhd:903:49  */
  assign n1614 = ~n1613;
  /* TG68K_ALU.vhd:907:55  */
  assign n1616 = ring + 6'b000001;
  /* TG68K_ALU.vhd:903:33  */
  assign n1618 = n1614 ? 6'b000000 : n1616;
  /* TG68K_ALU.vhd:891:17  */
  assign n1620 = n1624 ? 1'b0 : n1514;
  /* TG68K_ALU.vhd:902:25  */
  assign n1621 = n1612 ? n1618 : n1611;
  /* TG68K_ALU.vhd:902:25  */
  assign n1622 = n1614 & n1612;
  /* TG68K_ALU.vhd:891:17  */
  assign n1623 = n1599 ? n1621 : n1597;
  /* TG68K_ALU.vhd:891:17  */
  assign n1624 = n1622 & n1599;
  /* TG68K_ALU.vhd:915:50  */
  assign n1625 = asr_sign[31:0]; // extract
  /* TG68K_ALU.vhd:915:74  */
  assign n1626 = hot_msb[31:0]; // extract
  /* TG68K_ALU.vhd:915:64  */
  assign n1627 = n1625 | n1626;
  assign n1629 = n1628[0]; // extract
  /* TG68K_ALU.vhd:916:28  */
  assign n1631 = rot_bits == 2'b00;
  /* TG68K_ALU.vhd:916:48  */
  assign n1632 = exe_opcode[8]; // extract
  /* TG68K_ALU.vhd:916:51  */
  assign n1633 = ~n1632;
  /* TG68K_ALU.vhd:916:34  */
  assign n1634 = n1633 & n1631;
  /* TG68K_ALU.vhd:916:56  */
  assign n1635 = msb & n1634;
  /* TG68K_ALU.vhd:917:49  */
  assign n1636 = asr_sign[32:1]; // extract
  /* TG68K_ALU.vhd:917:38  */
  assign n1637 = alu | n1636;
  /* TG68K_ALU.vhd:918:37  */
  assign n1638 = $unsigned(bs_shift) > $unsigned(ring);
  /* TG68K_ALU.vhd:916:17  */
  assign n1640 = n1642 ? 1'b1 : n1620;
  /* TG68K_ALU.vhd:916:17  */
  assign n1641 = n1635 ? n1637 : alu;
  /* TG68K_ALU.vhd:916:17  */
  assign n1642 = n1638 & n1635;
  /* TG68K_ALU.vhd:923:43  */
  assign n1644 = {1'b0, OP1out};
  /* TG68K_ALU.vhd:924:32  */
  assign n1645 = exe_opcode[7:6]; // extract
  /* TG68K_ALU.vhd:926:46  */
  assign n1646 = OP1out[7]; // extract
  /* TG68K_ALU.vhd:929:44  */
  assign n1650 = rot_bits == 2'b10;
  /* TG68K_ALU.vhd:930:59  */
  assign n1651 = n2364[4]; // extract
  assign n1652 = n1647[0]; // extract
  /* TG68K_ALU.vhd:929:33  */
  assign n1653 = n1650 ? n1651 : n1652;
  assign n1654 = n1647[23:1]; // extract
  /* TG68K_ALU.vhd:925:25  */
  assign n1656 = n1645 == 2'b00;
  /* TG68K_ALU.vhd:933:46  */
  assign n1657 = OP1out[15]; // extract
  /* TG68K_ALU.vhd:936:44  */
  assign n1661 = rot_bits == 2'b10;
  /* TG68K_ALU.vhd:937:60  */
  assign n1662 = n2364[4]; // extract
  assign n1663 = n1658[0]; // extract
  /* TG68K_ALU.vhd:936:33  */
  assign n1664 = n1661 ? n1662 : n1663;
  assign n1665 = n1658[15:1]; // extract
  /* TG68K_ALU.vhd:932:25  */
  assign n1667 = n1645 == 2'b01;
  /* TG68K_ALU.vhd:932:34  */
  assign n1669 = n1645 == 2'b11;
  /* TG68K_ALU.vhd:932:34  */
  assign n1670 = n1667 | n1669;
  /* TG68K_ALU.vhd:940:46  */
  assign n1671 = OP1out[31]; // extract
  /* TG68K_ALU.vhd:941:44  */
  assign n1673 = rot_bits == 2'b10;
  /* TG68K_ALU.vhd:942:60  */
  assign n1674 = n2364[4]; // extract
  assign n1675 = n1644[32]; // extract
  /* TG68K_ALU.vhd:941:33  */
  assign n1676 = n1673 ? n1674 : n1675;
  /* TG68K_ALU.vhd:939:25  */
  assign n1678 = n1645 == 2'b10;
  assign n1679 = {n1678, n1670, n1656};
  assign n1680 = n1644[8]; // extract
  /* TG68K_ALU.vhd:924:17  */
  always @*
    case (n1679)
      3'b100: n1681 = n1680;
      3'b010: n1681 = n1680;
      3'b001: n1681 = n1653;
      default: n1681 = n1680;
    endcase
  assign n1682 = n1654[6:0]; // extract
  assign n1683 = n1644[15:9]; // extract
  /* TG68K_ALU.vhd:924:17  */
  always @*
    case (n1679)
      3'b100: n1684 = n1683;
      3'b010: n1684 = n1683;
      3'b001: n1684 = n1682;
      default: n1684 = n1683;
    endcase
  assign n1685 = n1654[7]; // extract
  assign n1686 = n1644[16]; // extract
  /* TG68K_ALU.vhd:924:17  */
  always @*
    case (n1679)
      3'b100: n1687 = n1686;
      3'b010: n1687 = n1664;
      3'b001: n1687 = n1685;
      default: n1687 = n1686;
    endcase
  assign n1688 = n1654[22:8]; // extract
  assign n1689 = n1644[31:17]; // extract
  /* TG68K_ALU.vhd:924:17  */
  always @*
    case (n1679)
      3'b100: n1690 = n1689;
      3'b010: n1690 = n1665;
      3'b001: n1690 = n1688;
      default: n1690 = n1689;
    endcase
  assign n1691 = n1644[32]; // extract
  /* TG68K_ALU.vhd:924:17  */
  always @*
    case (n1679)
      3'b100: n1692 = n1676;
      3'b010: n1692 = n1691;
      3'b001: n1692 = n1691;
      default: n1692 = n1691;
    endcase
  assign n1694 = n1644[7:0]; // extract
  /* TG68K_ALU.vhd:924:17  */
  always @*
    case (n1679)
      3'b100: n1698 = n1671;
      3'b010: n1698 = n1657;
      3'b001: n1698 = n1646;
      default: n1698 = msb;
    endcase
  assign n1699 = n1648[7:0]; // extract
  assign n1700 = n1641[15:8]; // extract
  /* TG68K_ALU.vhd:924:17  */
  always @*
    case (n1679)
      3'b100: n1701 = n1700;
      3'b010: n1701 = n1700;
      3'b001: n1701 = n1699;
      default: n1701 = n1700;
    endcase
  assign n1702 = n1648[23:8]; // extract
  assign n1703 = n1641[31:16]; // extract
  /* TG68K_ALU.vhd:924:17  */
  always @*
    case (n1679)
      3'b100: n1704 = n1703;
      3'b010: n1704 = 16'b0000000000000000;
      3'b001: n1704 = n1702;
      default: n1704 = n1703;
    endcase
  assign n1706 = n1641[7:0]; // extract
  /* TG68K_ALU.vhd:946:71  */
  assign n1708 = {33'b000000000000000000000000000000000, vector};
  /* TG68K_ALU.vhd:946:84  */
  assign n1709 = {25'b0, bit_nr};  //  uext
  /* TG68K_ALU.vhd:946:80  */
  assign n1710 = {1'b0, n1709};  //  uext
  /* TG68K_ALU.vhd:946:80  */
  assign n1711 = n1708 << n1710;
  /* TG68K_ALU.vhd:957:24  */
  assign n1715 = exec[17]; // extract
  /* TG68K_ALU.vhd:958:58  */
  assign n1716 = last_data_read[7:0]; // extract
  /* TG68K_ALU.vhd:958:40  */
  assign n1717 = n2364 & n1716;
  /* TG68K_ALU.vhd:959:27  */
  assign n1718 = exec[18]; // extract
  /* TG68K_ALU.vhd:960:58  */
  assign n1719 = last_data_read[7:0]; // extract
  /* TG68K_ALU.vhd:960:40  */
  assign n1720 = n2364 ^ n1719;
  /* TG68K_ALU.vhd:961:27  */
  assign n1721 = exec[19]; // extract
  /* TG68K_ALU.vhd:962:57  */
  assign n1722 = last_data_read[7:0]; // extract
  /* TG68K_ALU.vhd:962:40  */
  assign n1723 = n2364 | n1722;
  /* TG68K_ALU.vhd:964:40  */
  assign n1724 = OP2out[7:0]; // extract
  /* TG68K_ALU.vhd:961:17  */
  assign n1725 = n1721 ? n1723 : n1724;
  /* TG68K_ALU.vhd:959:17  */
  assign n1726 = n1718 ? n1720 : n1725;
  /* TG68K_ALU.vhd:957:17  */
  assign n1727 = n1715 ? n1717 : n1726;
  /* TG68K_ALU.vhd:971:24  */
  assign n1728 = exec[28]; // extract
  /* TG68K_ALU.vhd:971:50  */
  assign n1729 = n2364[2]; // extract
  /* TG68K_ALU.vhd:971:53  */
  assign n1730 = ~n1729;
  /* TG68K_ALU.vhd:971:41  */
  assign n1731 = n1730 & n1728;
  /* TG68K_ALU.vhd:973:28  */
  assign n1732 = op1in[7:0]; // extract
  /* TG68K_ALU.vhd:973:40  */
  assign n1734 = n1732 == 8'b00000000;
  /* TG68K_ALU.vhd:975:33  */
  assign n1736 = op1in[15:8]; // extract
  /* TG68K_ALU.vhd:975:46  */
  assign n1738 = n1736 == 8'b00000000;
  /* TG68K_ALU.vhd:977:41  */
  assign n1740 = op1in[31:16]; // extract
  /* TG68K_ALU.vhd:977:55  */
  assign n1742 = n1740 == 16'b0000000000000000;
  /* TG68K_ALU.vhd:977:33  */
  assign n1745 = n1742 ? 1'b1 : 1'b0;
  assign n1746 = {n1745, 1'b1};
  /* TG68K_ALU.vhd:975:25  */
  assign n1748 = n1738 ? n1746 : 2'b00;
  assign n1749 = {n1748, 1'b1};
  /* TG68K_ALU.vhd:973:17  */
  assign n1751 = n1734 ? n1749 : 3'b000;
  /* TG68K_ALU.vhd:971:17  */
  assign n1753 = n1731 ? 3'b000 : n1751;
  /* TG68K_ALU.vhd:984:32  */
  assign n1756 = exe_datatype == 2'b00;
  /* TG68K_ALU.vhd:985:43  */
  assign n1757 = op1in[7]; // extract
  /* TG68K_ALU.vhd:985:53  */
  assign n1758 = flag_z[0]; // extract
  /* TG68K_ALU.vhd:985:46  */
  assign n1759 = {n1757, n1758};
  /* TG68K_ALU.vhd:985:67  */
  assign n1760 = addsub_ofl[0]; // extract
  /* TG68K_ALU.vhd:985:56  */
  assign n1761 = {n1759, n1760};
  /* TG68K_ALU.vhd:985:76  */
  assign n1762 = n258[0]; // extract
  /* TG68K_ALU.vhd:985:70  */
  assign n1763 = {n1761, n1762};
  /* TG68K_ALU.vhd:986:32  */
  assign n1764 = exec[12]; // extract
  /* TG68K_ALU.vhd:986:53  */
  assign n1765 = exec[13]; // extract
  /* TG68K_ALU.vhd:986:46  */
  assign n1766 = n1764 | n1765;
  assign n1767 = {vflag_a, bcd_a_carry};
  assign n1768 = n1763[1:0]; // extract
  /* TG68K_ALU.vhd:986:25  */
  assign n1769 = n1766 ? n1767 : n1768;
  assign n1770 = n1763[3:2]; // extract
  /* TG68K_ALU.vhd:990:35  */
  assign n1772 = exe_datatype == 2'b10;
  /* TG68K_ALU.vhd:990:48  */
  assign n1773 = exec[10]; // extract
  /* TG68K_ALU.vhd:990:41  */
  assign n1774 = n1772 | n1773;
  /* TG68K_ALU.vhd:991:43  */
  assign n1775 = op1in[31]; // extract
  /* TG68K_ALU.vhd:991:54  */
  assign n1776 = flag_z[2]; // extract
  /* TG68K_ALU.vhd:991:47  */
  assign n1777 = {n1775, n1776};
  /* TG68K_ALU.vhd:991:68  */
  assign n1778 = addsub_ofl[2]; // extract
  /* TG68K_ALU.vhd:991:57  */
  assign n1779 = {n1777, n1778};
  /* TG68K_ALU.vhd:991:77  */
  assign n1780 = n258[2]; // extract
  /* TG68K_ALU.vhd:991:71  */
  assign n1781 = {n1779, n1780};
  /* TG68K_ALU.vhd:993:43  */
  assign n1782 = op1in[15]; // extract
  /* TG68K_ALU.vhd:993:54  */
  assign n1783 = flag_z[1]; // extract
  /* TG68K_ALU.vhd:993:47  */
  assign n1784 = {n1782, n1783};
  /* TG68K_ALU.vhd:993:68  */
  assign n1785 = addsub_ofl[1]; // extract
  /* TG68K_ALU.vhd:993:57  */
  assign n1786 = {n1784, n1785};
  /* TG68K_ALU.vhd:993:77  */
  assign n1787 = n258[1]; // extract
  /* TG68K_ALU.vhd:993:71  */
  assign n1788 = {n1786, n1787};
  /* TG68K_ALU.vhd:990:17  */
  assign n1789 = n1774 ? n1781 : n1788;
  assign n1790 = {n1770, n1769};
  /* TG68K_ALU.vhd:984:17  */
  assign n1791 = n1756 ? n1790 : n1789;
  /* TG68K_ALU.vhd:1000:40  */
  assign n1793 = exec[59]; // extract
  /* TG68K_ALU.vhd:1000:55  */
  assign n1794 = n1793 | set_stop;
  /* TG68K_ALU.vhd:1001:71  */
  assign n1795 = data_read[7:0]; // extract
  /* TG68K_ALU.vhd:1000:33  */
  assign n1796 = n1794 ? n1795 : n2364;
  /* TG68K_ALU.vhd:1003:40  */
  assign n1797 = exec[60]; // extract
  /* TG68K_ALU.vhd:1004:71  */
  assign n1798 = data_read[7:0]; // extract
  /* TG68K_ALU.vhd:1003:33  */
  assign n1799 = n1797 ? n1798 : n1796;
  /* TG68K_ALU.vhd:1007:40  */
  assign n1800 = exec[9]; // extract
  /* TG68K_ALU.vhd:1007:66  */
  assign n1801 = ~decodeOPC;
  /* TG68K_ALU.vhd:1007:53  */
  assign n1802 = n1801 & n1800;
  /* TG68K_ALU.vhd:1008:65  */
  assign n1803 = set_flags[3]; // extract
  /* TG68K_ALU.vhd:1008:69  */
  assign n1804 = n1803 ^ rot_rot;
  /* TG68K_ALU.vhd:1008:82  */
  assign n1805 = n1804 | asl_vflag;
  /* TG68K_ALU.vhd:1007:33  */
  assign n1807 = n1802 ? n1805 : 1'b0;
  /* TG68K_ALU.vhd:1012:40  */
  assign n1808 = exec[51]; // extract
  /* TG68K_ALU.vhd:1015:56  */
  assign n1810 = micro_state == 7'b0110011;
  /* TG68K_ALU.vhd:1017:62  */
  assign n1811 = exe_opcode[8]; // extract
  /* TG68K_ALU.vhd:1017:65  */
  assign n1812 = ~n1811;
  /* TG68K_ALU.vhd:1019:92  */
  assign n1813 = reg_QA[31]; // extract
  /* TG68K_ALU.vhd:1019:82  */
  assign n1814 = ~n1813;
  /* TG68K_ALU.vhd:1019:81  */
  assign n1816 = {1'b0, n1814};
  /* TG68K_ALU.vhd:1019:96  */
  assign n1818 = {n1816, 2'b00};
  /* TG68K_ALU.vhd:1017:49  */
  assign n1820 = n1812 ? n1818 : 4'b0100;
  assign n1821 = n1799[3:0]; // extract
  /* TG68K_ALU.vhd:1015:41  */
  assign n1822 = n1810 ? n1820 : n1821;
  /* TG68K_ALU.vhd:1024:43  */
  assign n1823 = exec[49]; // extract
  /* TG68K_ALU.vhd:1024:53  */
  assign n1824 = ~n1823;
  /* TG68K_ALU.vhd:1025:61  */
  assign n1825 = n2364[3:0]; // extract
  /* TG68K_ALU.vhd:1026:48  */
  assign n1826 = exec[3]; // extract
  /* TG68K_ALU.vhd:1027:70  */
  assign n1827 = set_flags[0]; // extract
  /* TG68K_ALU.vhd:1028:51  */
  assign n1828 = exec[9]; // extract
  /* TG68K_ALU.vhd:1028:76  */
  assign n1830 = rot_bits != 2'b11;
  /* TG68K_ALU.vhd:1028:64  */
  assign n1831 = n1830 & n1828;
  /* TG68K_ALU.vhd:1028:91  */
  assign n1832 = exec[23]; // extract
  /* TG68K_ALU.vhd:1028:100  */
  assign n1833 = ~n1832;
  /* TG68K_ALU.vhd:1028:83  */
  assign n1834 = n1833 & n1831;
  /* TG68K_ALU.vhd:1030:51  */
  assign n1835 = exec[81]; // extract
  assign n1836 = n1799[4]; // extract
  /* TG68K_ALU.vhd:1030:41  */
  assign n1837 = n1835 ? bs_x : n1836;
  /* TG68K_ALU.vhd:1028:41  */
  assign n1838 = n1834 ? rot_x : n1837;
  /* TG68K_ALU.vhd:1026:41  */
  assign n1839 = n1826 ? n1827 : n1838;
  /* TG68K_ALU.vhd:1034:49  */
  assign n1840 = exec[8]; // extract
  /* TG68K_ALU.vhd:1034:65  */
  assign n1841 = exec[86]; // extract
  /* TG68K_ALU.vhd:1034:58  */
  assign n1842 = n1840 | n1841;
  /* TG68K_ALU.vhd:1036:51  */
  assign n1843 = exec[21]; // extract
  /* TG68K_ALU.vhd:1036:65  */
  assign n1845 = 1'b1 & n1843;
  /* TG68K_ALU.vhd:1039:65  */
  assign n1847 = exe_opcode[15]; // extract
  /* TG68K_ALU.vhd:1039:74  */
  assign n1849 = n1847 | 1'b0;
  /* TG68K_ALU.vhd:1040:83  */
  assign n1850 = op1in[15]; // extract
  /* TG68K_ALU.vhd:1040:94  */
  assign n1851 = flag_z[1]; // extract
  /* TG68K_ALU.vhd:1040:87  */
  assign n1852 = {n1850, n1851};
  /* TG68K_ALU.vhd:1040:97  */
  assign n1854 = {n1852, 2'b00};
  /* TG68K_ALU.vhd:1042:83  */
  assign n1855 = op1in[31]; // extract
  /* TG68K_ALU.vhd:1042:94  */
  assign n1856 = flag_z[2]; // extract
  /* TG68K_ALU.vhd:1042:87  */
  assign n1857 = {n1855, n1856};
  /* TG68K_ALU.vhd:1042:97  */
  assign n1859 = {n1857, 2'b00};
  /* TG68K_ALU.vhd:1039:49  */
  assign n1860 = n1849 ? n1854 : n1859;
  /* TG68K_ALU.vhd:1037:49  */
  assign n1861 = v_flag ? 4'b1010 : n1860;
  /* TG68K_ALU.vhd:1044:51  */
  assign n1862 = exec[68]; // extract
  /* TG68K_ALU.vhd:1044:72  */
  assign n1864 = 1'b1 & n1862;
  /* TG68K_ALU.vhd:1045:70  */
  assign n1865 = set_flags[3]; // extract
  /* TG68K_ALU.vhd:1046:70  */
  assign n1866 = set_flags[2]; // extract
  /* TG68K_ALU.vhd:1046:83  */
  assign n1867 = n2364[2]; // extract
  /* TG68K_ALU.vhd:1046:74  */
  assign n1868 = n1866 & n1867;
  /* TG68K_ALU.vhd:1054:51  */
  assign n1872 = exec[5]; // extract
  /* TG68K_ALU.vhd:1054:70  */
  assign n1873 = exec[6]; // extract
  /* TG68K_ALU.vhd:1054:63  */
  assign n1874 = n1872 | n1873;
  /* TG68K_ALU.vhd:1054:90  */
  assign n1875 = exec[7]; // extract
  /* TG68K_ALU.vhd:1054:83  */
  assign n1876 = n1874 | n1875;
  /* TG68K_ALU.vhd:1054:110  */
  assign n1877 = exec[0]; // extract
  /* TG68K_ALU.vhd:1054:103  */
  assign n1878 = n1876 | n1877;
  /* TG68K_ALU.vhd:1054:131  */
  assign n1879 = exec[1]; // extract
  /* TG68K_ALU.vhd:1054:124  */
  assign n1880 = n1878 | n1879;
  /* TG68K_ALU.vhd:1054:153  */
  assign n1881 = exec[15]; // extract
  /* TG68K_ALU.vhd:1054:146  */
  assign n1882 = n1880 | n1881;
  /* TG68K_ALU.vhd:1054:174  */
  assign n1883 = exec[75]; // extract
  /* TG68K_ALU.vhd:1054:167  */
  assign n1884 = n1882 | n1883;
  /* TG68K_ALU.vhd:1054:194  */
  assign n1885 = exec[20]; // extract
  /* TG68K_ALU.vhd:1054:208  */
  assign n1887 = 1'b1 & n1885;
  /* TG68K_ALU.vhd:1054:186  */
  assign n1888 = n1884 | n1887;
  /* TG68K_ALU.vhd:1057:56  */
  assign n1891 = exec[75]; // extract
  assign n1892 = set_flags[3]; // extract
  /* TG68K_ALU.vhd:1057:49  */
  assign n1893 = n1891 ? bf_nflag : n1892;
  assign n1894 = set_flags[2]; // extract
  /* TG68K_ALU.vhd:1060:51  */
  assign n1895 = exec[9]; // extract
  /* TG68K_ALU.vhd:1061:79  */
  assign n1896 = set_flags[3:2]; // extract
  /* TG68K_ALU.vhd:1063:60  */
  assign n1898 = rot_bits == 2'b00;
  /* TG68K_ALU.vhd:1063:81  */
  assign n1899 = set_flags[3]; // extract
  /* TG68K_ALU.vhd:1063:85  */
  assign n1900 = n1899 ^ rot_rot;
  /* TG68K_ALU.vhd:1063:98  */
  assign n1901 = n1900 | asl_vflag;
  /* TG68K_ALU.vhd:1063:66  */
  assign n1902 = n1901 & n1898;
  /* TG68K_ALU.vhd:1063:49  */
  assign n1905 = n1902 ? 1'b1 : 1'b0;
  /* TG68K_ALU.vhd:1068:51  */
  assign n1906 = exec[81]; // extract
  /* TG68K_ALU.vhd:1069:79  */
  assign n1907 = set_flags[3:2]; // extract
  /* TG68K_ALU.vhd:1072:51  */
  assign n1908 = exec[14]; // extract
  /* TG68K_ALU.vhd:1073:61  */
  assign n1909 = ~one_bit_in;
  /* TG68K_ALU.vhd:1074:51  */
  assign n1910 = exec[87]; // extract
  /* TG68K_ALU.vhd:1079:63  */
  assign n1911 = last_flags1[0]; // extract
  /* TG68K_ALU.vhd:1079:66  */
  assign n1912 = ~n1911;
  /* TG68K_ALU.vhd:1080:74  */
  assign n1913 = n2364[0]; // extract
  /* TG68K_ALU.vhd:1080:95  */
  assign n1914 = set_flags[0]; // extract
  /* TG68K_ALU.vhd:1080:82  */
  assign n1915 = ~n1914;
  /* TG68K_ALU.vhd:1080:116  */
  assign n1916 = set_flags[2]; // extract
  /* TG68K_ALU.vhd:1080:103  */
  assign n1917 = ~n1916;
  /* TG68K_ALU.vhd:1080:99  */
  assign n1918 = n1915 & n1917;
  /* TG68K_ALU.vhd:1080:78  */
  assign n1919 = n1913 | n1918;
  /* TG68K_ALU.vhd:1082:75  */
  assign n1920 = n2364[0]; // extract
  /* TG68K_ALU.vhd:1082:92  */
  assign n1921 = set_flags[0]; // extract
  /* TG68K_ALU.vhd:1082:79  */
  assign n1922 = n1920 ^ n1921;
  /* TG68K_ALU.vhd:1082:111  */
  assign n1923 = n2364[2]; // extract
  /* TG68K_ALU.vhd:1082:102  */
  assign n1924 = ~n1923;
  /* TG68K_ALU.vhd:1082:97  */
  assign n1925 = n1922 & n1924;
  /* TG68K_ALU.vhd:1082:132  */
  assign n1926 = set_flags[2]; // extract
  /* TG68K_ALU.vhd:1082:119  */
  assign n1927 = ~n1926;
  /* TG68K_ALU.vhd:1082:115  */
  assign n1928 = n1925 & n1927;
  /* TG68K_ALU.vhd:1079:49  */
  assign n1929 = n1912 ? n1919 : n1928;
  /* TG68K_ALU.vhd:1085:66  */
  assign n1931 = n2364[2]; // extract
  /* TG68K_ALU.vhd:1085:82  */
  assign n1932 = set_flags[2]; // extract
  /* TG68K_ALU.vhd:1085:70  */
  assign n1933 = n1931 | n1932;
  /* TG68K_ALU.vhd:1086:76  */
  assign n1934 = last_flags1[0]; // extract
  /* TG68K_ALU.vhd:1086:61  */
  assign n1935 = ~n1934;
  /* TG68K_ALU.vhd:1087:51  */
  assign n1936 = exec[31]; // extract
  /* TG68K_ALU.vhd:1088:64  */
  assign n1938 = exe_datatype == 2'b01;
  /* TG68K_ALU.vhd:1089:75  */
  assign n1939 = OP1out[15]; // extract
  /* TG68K_ALU.vhd:1091:75  */
  assign n1940 = OP1out[31]; // extract
  /* TG68K_ALU.vhd:1088:49  */
  assign n1941 = n1938 ? n1939 : n1940;
  /* TG68K_ALU.vhd:1093:58  */
  assign n1942 = OP1out[15:0]; // extract
  /* TG68K_ALU.vhd:1093:71  */
  assign n1944 = n1942 == 16'b0000000000000000;
  /* TG68K_ALU.vhd:1093:97  */
  assign n1946 = exe_datatype == 2'b01;
  /* TG68K_ALU.vhd:1093:112  */
  assign n1947 = OP1out[31:16]; // extract
  /* TG68K_ALU.vhd:1093:126  */
  assign n1949 = n1947 == 16'b0000000000000000;
  /* TG68K_ALU.vhd:1093:103  */
  assign n1950 = n1946 | n1949;
  /* TG68K_ALU.vhd:1093:80  */
  assign n1951 = n1950 & n1944;
  /* TG68K_ALU.vhd:1093:49  */
  assign n1954 = n1951 ? 1'b1 : 1'b0;
  assign n1957 = {n1941, n1954, 1'b0, 1'b0};
  assign n1958 = n1799[3:0]; // extract
  /* TG68K_ALU.vhd:1087:41  */
  assign n1959 = n1936 ? n1957 : n1958;
  assign n1960 = {n1935, n1933, 1'b0, n1929};
  /* TG68K_ALU.vhd:1074:41  */
  assign n1961 = n1910 ? n1960 : n1959;
  assign n1962 = n1961[1:0]; // extract
  assign n1963 = n1799[1:0]; // extract
  /* TG68K_ALU.vhd:1072:41  */
  assign n1964 = n1908 ? n1963 : n1962;
  assign n1965 = n1961[2]; // extract
  /* TG68K_ALU.vhd:1072:41  */
  assign n1966 = n1908 ? n1909 : n1965;
  assign n1967 = n1961[3]; // extract
  assign n1968 = n1799[3]; // extract
  /* TG68K_ALU.vhd:1072:41  */
  assign n1969 = n1908 ? n1968 : n1967;
  assign n1970 = {n1969, n1966, n1964};
  assign n1971 = {n1907, bs_v, bs_c};
  /* TG68K_ALU.vhd:1068:41  */
  assign n1972 = n1906 ? n1971 : n1970;
  assign n1973 = {n1896, n1905, rot_c};
  /* TG68K_ALU.vhd:1060:41  */
  assign n1974 = n1895 ? n1973 : n1972;
  assign n1975 = {n1893, n1894, 2'b00};
  /* TG68K_ALU.vhd:1054:41  */
  assign n1976 = n1888 ? n1975 : n1974;
  assign n1977 = {n1865, n1868, 1'b0, 1'b0};
  /* TG68K_ALU.vhd:1044:41  */
  assign n1978 = n1864 ? n1977 : n1976;
  /* TG68K_ALU.vhd:1036:41  */
  assign n1979 = n1845 ? n1861 : n1978;
  /* TG68K_ALU.vhd:1034:41  */
  assign n1980 = n1842 ? set_flags : n1979;
  assign n1981 = {n1839, n1980};
  assign n1982 = n1799[4:0]; // extract
  /* TG68K_ALU.vhd:1024:33  */
  assign n1983 = n1824 ? n1981 : n1982;
  /* TG68K_ALU.vhd:1024:33  */
  assign n1984 = n1824 ? n1825 : last_flags1;
  assign n1985 = n1983[3:0]; // extract
  /* TG68K_ALU.vhd:1014:33  */
  assign n1986 = Z_error ? n1822 : n1985;
  assign n1987 = n1983[4]; // extract
  assign n1988 = n1799[4]; // extract
  /* TG68K_ALU.vhd:1014:33  */
  assign n1989 = Z_error ? n1988 : n1987;
  /* TG68K_ALU.vhd:1014:33  */
  assign n1990 = Z_error ? last_flags1 : n1984;
  assign n1991 = {n1989, n1986};
  assign n1992 = ccrin[4:0]; // extract
  /* TG68K_ALU.vhd:1012:33  */
  assign n1993 = n1808 ? n1992 : n1991;
  assign n1994 = ccrin[7:5]; // extract
  assign n1995 = n1799[7:5]; // extract
  /* TG68K_ALU.vhd:1012:33  */
  assign n1996 = n1808 ? n1994 : n1995;
  /* TG68K_ALU.vhd:1012:33  */
  assign n1998 = n1808 ? last_flags1 : n1990;
  assign n1999 = {n1996, n1993};
  /* TG68K_ALU.vhd:999:25  */
  assign n2000 = clkena_lw ? n1999 : n2364;
  /* TG68K_ALU.vhd:999:25  */
  assign n2001 = clkena_lw ? n1998 : last_flags1;
  /* TG68K_ALU.vhd:999:25  */
  assign n2002 = clkena_lw ? n1807 : asl_vflag;
  /* TG68K_ALU.vhd:997:25  */
  assign n2004 = Reset ? 8'b00000000 : n2000;
  /* TG68K_ALU.vhd:997:25  */
  assign n2005 = Reset ? last_flags1 : n2001;
  /* TG68K_ALU.vhd:997:25  */
  assign n2006 = Reset ? asl_vflag : n2002;
  assign n2008 = n2004[4:0]; // extract
  assign n2009 = {3'b000, n2008};
  /* TG68K_ALU.vhd:1162:45  */
  assign n2016 = faktorb[31]; // extract
  /* TG68K_ALU.vhd:1162:34  */
  assign n2017 = n2016 & signedop;
  /* TG68K_ALU.vhd:1162:55  */
  assign n2018 = n2017 | fasign;
  /* TG68K_ALU.vhd:1163:45  */
  assign n2019 = mulu_reg[63]; // extract
  /* TG68K_ALU.vhd:1162:17  */
  assign n2021 = n2018 ? n2019 : 1'b0;
  /* TG68K_ALU.vhd:1168:44  */
  assign n2022 = faktorb[31]; // extract
  /* TG68K_ALU.vhd:1168:33  */
  assign n2023 = n2022 & signedop;
  /* TG68K_ALU.vhd:1168:17  */
  assign n2026 = n2023 ? 1'b1 : 1'b0;
  /* TG68K_ALU.vhd:1185:70  */
  assign n2027 = mulu_reg[63:1]; // extract
  /* TG68K_ALU.vhd:1185:61  */
  assign n2028 = {muls_msb, n2027};
  /* TG68K_ALU.vhd:1186:36  */
  assign n2029 = mulu_reg[0]; // extract
  /* TG68K_ALU.vhd:1188:88  */
  assign n2030 = mulu_reg[63:32]; // extract
  /* TG68K_ALU.vhd:1188:79  */
  assign n2031 = {muls_msb, n2030};
  /* TG68K_ALU.vhd:1188:113  */
  assign n2032 = {mulu_sign, faktorb};
  /* TG68K_ALU.vhd:1188:102  */
  assign n2033 = n2031 - n2032;
  /* TG68K_ALU.vhd:1190:88  */
  assign n2034 = mulu_reg[63:32]; // extract
  /* TG68K_ALU.vhd:1190:79  */
  assign n2035 = {muls_msb, n2034};
  /* TG68K_ALU.vhd:1190:113  */
  assign n2036 = {mulu_sign, faktorb};
  /* TG68K_ALU.vhd:1190:102  */
  assign n2037 = n2035 + n2036;
  /* TG68K_ALU.vhd:1187:33  */
  assign n2038 = fasign ? n2033 : n2037;
  assign n2039 = n2028[63:31]; // extract
  /* TG68K_ALU.vhd:1186:25  */
  assign n2040 = n2029 ? n2038 : n2039;
  assign n2041 = n2028[30:0]; // extract
  /* TG68K_ALU.vhd:1194:30  */
  assign n2042 = exe_opcode[15]; // extract
  /* TG68K_ALU.vhd:1194:39  */
  assign n2044 = n2042 | 1'b0;
  /* TG68K_ALU.vhd:1195:56  */
  assign n2045 = OP2out[15:0]; // extract
  assign n2047 = {n2045, 16'b0000000000000000};
  /* TG68K_ALU.vhd:1194:17  */
  assign n2048 = n2044 ? n2047 : OP2out;
  /* TG68K_ALU.vhd:1227:77  */
  assign n2071 = result_mulu[63:32]; // extract
  /* TG68K_ALU.vhd:1240:32  */
  assign n2079 = opcode[15]; // extract
  /* TG68K_ALU.vhd:1240:47  */
  assign n2080 = opcode[8]; // extract
  /* TG68K_ALU.vhd:1240:37  */
  assign n2081 = n2079 & n2080;
  /* TG68K_ALU.vhd:1240:66  */
  assign n2082 = opcode[15]; // extract
  /* TG68K_ALU.vhd:1240:56  */
  assign n2083 = ~n2082;
  /* TG68K_ALU.vhd:1240:81  */
  assign n2084 = sndOPC[11]; // extract
  /* TG68K_ALU.vhd:1240:71  */
  assign n2085 = n2083 & n2084;
  /* TG68K_ALU.vhd:1240:52  */
  assign n2086 = n2081 | n2085;
  /* TG68K_ALU.vhd:1242:68  */
  assign n2088 = reg_QA[31]; // extract
  /* TG68K_ALU.vhd:1242:58  */
  assign n2089 = divs & n2088;
  /* TG68K_ALU.vhd:1242:68  */
  assign n2090 = reg_QA[31]; // extract
  /* TG68K_ALU.vhd:1242:58  */
  assign n2091 = divs & n2090;
  /* TG68K_ALU.vhd:1242:68  */
  assign n2092 = reg_QA[31]; // extract
  /* TG68K_ALU.vhd:1242:58  */
  assign n2093 = divs & n2092;
  /* TG68K_ALU.vhd:1242:68  */
  assign n2094 = reg_QA[31]; // extract
  /* TG68K_ALU.vhd:1242:58  */
  assign n2095 = divs & n2094;
  /* TG68K_ALU.vhd:1242:68  */
  assign n2096 = reg_QA[31]; // extract
  /* TG68K_ALU.vhd:1242:58  */
  assign n2097 = divs & n2096;
  /* TG68K_ALU.vhd:1242:68  */
  assign n2098 = reg_QA[31]; // extract
  /* TG68K_ALU.vhd:1242:58  */
  assign n2099 = divs & n2098;
  /* TG68K_ALU.vhd:1242:68  */
  assign n2100 = reg_QA[31]; // extract
  /* TG68K_ALU.vhd:1242:58  */
  assign n2101 = divs & n2100;
  /* TG68K_ALU.vhd:1242:68  */
  assign n2102 = reg_QA[31]; // extract
  /* TG68K_ALU.vhd:1242:58  */
  assign n2103 = divs & n2102;
  /* TG68K_ALU.vhd:1242:68  */
  assign n2104 = reg_QA[31]; // extract
  /* TG68K_ALU.vhd:1242:58  */
  assign n2105 = divs & n2104;
  /* TG68K_ALU.vhd:1242:68  */
  assign n2106 = reg_QA[31]; // extract
  /* TG68K_ALU.vhd:1242:58  */
  assign n2107 = divs & n2106;
  /* TG68K_ALU.vhd:1242:68  */
  assign n2108 = reg_QA[31]; // extract
  /* TG68K_ALU.vhd:1242:58  */
  assign n2109 = divs & n2108;
  /* TG68K_ALU.vhd:1242:68  */
  assign n2110 = reg_QA[31]; // extract
  /* TG68K_ALU.vhd:1242:58  */
  assign n2111 = divs & n2110;
  /* TG68K_ALU.vhd:1242:68  */
  assign n2112 = reg_QA[31]; // extract
  /* TG68K_ALU.vhd:1242:58  */
  assign n2113 = divs & n2112;
  /* TG68K_ALU.vhd:1242:68  */
  assign n2114 = reg_QA[31]; // extract
  /* TG68K_ALU.vhd:1242:58  */
  assign n2115 = divs & n2114;
  /* TG68K_ALU.vhd:1242:68  */
  assign n2116 = reg_QA[31]; // extract
  /* TG68K_ALU.vhd:1242:58  */
  assign n2117 = divs & n2116;
  /* TG68K_ALU.vhd:1242:68  */
  assign n2118 = reg_QA[31]; // extract
  /* TG68K_ALU.vhd:1242:58  */
  assign n2119 = divs & n2118;
  /* TG68K_ALU.vhd:1242:68  */
  assign n2120 = reg_QA[31]; // extract
  /* TG68K_ALU.vhd:1242:58  */
  assign n2121 = divs & n2120;
  /* TG68K_ALU.vhd:1242:68  */
  assign n2122 = reg_QA[31]; // extract
  /* TG68K_ALU.vhd:1242:58  */
  assign n2123 = divs & n2122;
  /* TG68K_ALU.vhd:1242:68  */
  assign n2124 = reg_QA[31]; // extract
  /* TG68K_ALU.vhd:1242:58  */
  assign n2125 = divs & n2124;
  /* TG68K_ALU.vhd:1242:68  */
  assign n2126 = reg_QA[31]; // extract
  /* TG68K_ALU.vhd:1242:58  */
  assign n2127 = divs & n2126;
  /* TG68K_ALU.vhd:1242:68  */
  assign n2128 = reg_QA[31]; // extract
  /* TG68K_ALU.vhd:1242:58  */
  assign n2129 = divs & n2128;
  /* TG68K_ALU.vhd:1242:68  */
  assign n2130 = reg_QA[31]; // extract
  /* TG68K_ALU.vhd:1242:58  */
  assign n2131 = divs & n2130;
  /* TG68K_ALU.vhd:1242:68  */
  assign n2132 = reg_QA[31]; // extract
  /* TG68K_ALU.vhd:1242:58  */
  assign n2133 = divs & n2132;
  /* TG68K_ALU.vhd:1242:68  */
  assign n2134 = reg_QA[31]; // extract
  /* TG68K_ALU.vhd:1242:58  */
  assign n2135 = divs & n2134;
  /* TG68K_ALU.vhd:1242:68  */
  assign n2136 = reg_QA[31]; // extract
  /* TG68K_ALU.vhd:1242:58  */
  assign n2137 = divs & n2136;
  /* TG68K_ALU.vhd:1242:68  */
  assign n2138 = reg_QA[31]; // extract
  /* TG68K_ALU.vhd:1242:58  */
  assign n2139 = divs & n2138;
  /* TG68K_ALU.vhd:1242:68  */
  assign n2140 = reg_QA[31]; // extract
  /* TG68K_ALU.vhd:1242:58  */
  assign n2141 = divs & n2140;
  /* TG68K_ALU.vhd:1242:68  */
  assign n2142 = reg_QA[31]; // extract
  /* TG68K_ALU.vhd:1242:58  */
  assign n2143 = divs & n2142;
  /* TG68K_ALU.vhd:1242:68  */
  assign n2144 = reg_QA[31]; // extract
  /* TG68K_ALU.vhd:1242:58  */
  assign n2145 = divs & n2144;
  /* TG68K_ALU.vhd:1242:68  */
  assign n2146 = reg_QA[31]; // extract
  /* TG68K_ALU.vhd:1242:58  */
  assign n2147 = divs & n2146;
  /* TG68K_ALU.vhd:1242:68  */
  assign n2148 = reg_QA[31]; // extract
  /* TG68K_ALU.vhd:1242:58  */
  assign n2149 = divs & n2148;
  /* TG68K_ALU.vhd:1242:68  */
  assign n2150 = reg_QA[31]; // extract
  /* TG68K_ALU.vhd:1242:58  */
  assign n2151 = divs & n2150;
  assign n2152 = {n2089, n2091, n2093, n2095};
  assign n2153 = {n2097, n2099, n2101, n2103};
  assign n2154 = {n2105, n2107, n2109, n2111};
  assign n2155 = {n2113, n2115, n2117, n2119};
  assign n2156 = {n2121, n2123, n2125, n2127};
  assign n2157 = {n2129, n2131, n2133, n2135};
  assign n2158 = {n2137, n2139, n2141, n2143};
  assign n2159 = {n2145, n2147, n2149, n2151};
  assign n2160 = {n2152, n2153, n2154, n2155};
  assign n2161 = {n2156, n2157, n2158, n2159};
  assign n2162 = {n2160, n2161};
  /* TG68K_ALU.vhd:1243:30  */
  assign n2163 = exe_opcode[15]; // extract
  /* TG68K_ALU.vhd:1243:39  */
  assign n2165 = n2163 | 1'b0;
  /* TG68K_ALU.vhd:1245:52  */
  assign n2166 = result_div_pre[15]; // extract
  /* TG68K_ALU.vhd:1248:38  */
  assign n2167 = exe_opcode[14]; // extract
  /* TG68K_ALU.vhd:1248:57  */
  assign n2168 = sndOPC[10]; // extract
  /* TG68K_ALU.vhd:1248:47  */
  assign n2169 = n2168 & n2167;
  /* TG68K_ALU.vhd:1248:25  */
  assign n2170 = n2169 ? reg_QB : n2162;
  /* TG68K_ALU.vhd:1251:52  */
  assign n2171 = result_div_pre[31]; // extract
  /* TG68K_ALU.vhd:1243:17  */
  assign n2172 = n2165 ? n2166 : n2171;
  assign n2173 = {n2170, reg_QA};
  assign n2174 = n2173[15:0]; // extract
  /* TG68K_ALU.vhd:1243:17  */
  assign n2175 = n2165 ? 16'b0000000000000000 : n2174;
  assign n2176 = n2173[47:16]; // extract
  /* TG68K_ALU.vhd:1243:17  */
  assign n2177 = n2165 ? reg_QA : n2176;
  assign n2178 = n2173[63:48]; // extract
  assign n2179 = n2162[31:16]; // extract
  /* TG68K_ALU.vhd:1243:17  */
  assign n2180 = n2165 ? n2179 : n2178;
  /* TG68K_ALU.vhd:1253:42  */
  assign n2182 = opcode[15]; // extract
  /* TG68K_ALU.vhd:1253:46  */
  assign n2183 = ~n2182;
  /* TG68K_ALU.vhd:1253:33  */
  assign n2184 = signedop | n2183;
  /* TG68K_ALU.vhd:1254:44  */
  assign n2185 = OP2out[31:16]; // extract
  /* TG68K_ALU.vhd:1253:17  */
  assign n2187 = n2184 ? n2185 : 16'b0000000000000000;
  /* TG68K_ALU.vhd:1258:43  */
  assign n2188 = OP2out[31]; // extract
  /* TG68K_ALU.vhd:1258:33  */
  assign n2189 = n2188 & signedop;
  /* TG68K_ALU.vhd:1259:44  */
  assign n2190 = div_reg[63:31]; // extract
  /* TG68K_ALU.vhd:1259:64  */
  assign n2192 = {1'b1, OP2out};
  /* TG68K_ALU.vhd:1259:59  */
  assign n2193 = n2190 + n2192;
  /* TG68K_ALU.vhd:1261:44  */
  assign n2194 = div_reg[63:31]; // extract
  /* TG68K_ALU.vhd:1261:64  */
  assign n2196 = {1'b0, op2outext};
  /* TG68K_ALU.vhd:1261:94  */
  assign n2197 = OP2out[15:0]; // extract
  /* TG68K_ALU.vhd:1261:87  */
  assign n2198 = {n2196, n2197};
  /* TG68K_ALU.vhd:1261:59  */
  assign n2199 = n2194 - n2198;
  /* TG68K_ALU.vhd:1258:17  */
  assign n2200 = n2189 ? n2193 : n2199;
  /* TG68K_ALU.vhd:1266:43  */
  assign n2201 = div_sub[32]; // extract
  /* TG68K_ALU.vhd:1269:58  */
  assign n2202 = div_reg[62:31]; // extract
  /* TG68K_ALU.vhd:1271:58  */
  assign n2203 = div_sub[31:0]; // extract
  /* TG68K_ALU.vhd:1268:17  */
  assign n2204 = div_bit ? n2202 : n2203;
  /* TG68K_ALU.vhd:1273:49  */
  assign n2205 = div_reg[30:0]; // extract
  /* TG68K_ALU.vhd:1273:63  */
  assign n2206 = ~div_bit;
  /* TG68K_ALU.vhd:1273:62  */
  assign n2207 = {n2205, n2206};
  /* TG68K_ALU.vhd:1276:66  */
  assign n2208 = div_quot[31:0]; // extract
  /* TG68K_ALU.vhd:1276:57  */
  assign n2210 = 32'b00000000000000000000000000000000 - n2208;
  /* TG68K_ALU.vhd:1279:64  */
  assign n2211 = div_quot[31:0]; // extract
  /* TG68K_ALU.vhd:1275:17  */
  assign n2212 = div_neg ? n2210 : n2211;
  /* TG68K_ALU.vhd:1282:44  */
  assign n2213 = ~div_bit;
  /* TG68K_ALU.vhd:1282:34  */
  assign n2214 = nozero | n2213;
  /* TG68K_ALU.vhd:1282:50  */
  assign n2215 = signedop & n2214;
  /* TG68K_ALU.vhd:1282:78  */
  assign n2216 = OP2out[31]; // extract
  /* TG68K_ALU.vhd:1282:83  */
  assign n2217 = n2216 ^ op1_sign;
  /* TG68K_ALU.vhd:1282:96  */
  assign n2218 = n2217 ^ div_qsign;
  /* TG68K_ALU.vhd:1282:67  */
  assign n2219 = n2218 & n2215;
  /* TG68K_ALU.vhd:1283:37  */
  assign n2220 = ~signedop;
  /* TG68K_ALU.vhd:1283:54  */
  assign n2221 = div_over[32]; // extract
  /* TG68K_ALU.vhd:1283:58  */
  assign n2222 = ~n2221;
  /* TG68K_ALU.vhd:1283:42  */
  assign n2223 = n2222 & n2220;
  /* TG68K_ALU.vhd:1283:25  */
  assign n2224 = n2219 | n2223;
  /* TG68K_ALU.vhd:1283:65  */
  assign n2226 = 1'b1 & n2224;
  /* TG68K_ALU.vhd:1282:17  */
  assign n2229 = n2226 ? 1'b1 : 1'b0;
  /* TG68K_ALU.vhd:1294:47  */
  assign n2235 = micro_state != 7'b1011010;
  /* TG68K_ALU.vhd:1298:47  */
  assign n2238 = micro_state == 7'b1010101;
  /* TG68K_ALU.vhd:1300:65  */
  assign n2239 = dividend[63]; // extract
  /* TG68K_ALU.vhd:1300:53  */
  assign n2240 = n2239 & divs;
  /* TG68K_ALU.vhd:1302:61  */
  assign n2242 = 64'b0000000000000000000000000000000000000000000000000000000000000000 - dividend;
  /* TG68K_ALU.vhd:1300:41  */
  assign n2243 = n2240 ? n2242 : dividend;
  /* TG68K_ALU.vhd:1300:41  */
  assign n2246 = n2240 ? 1'b1 : 1'b0;
  /* TG68K_ALU.vhd:1309:51  */
  assign n2247 = ~div_bit;
  /* TG68K_ALU.vhd:1309:63  */
  assign n2248 = n2247 | nozero;
  /* TG68K_ALU.vhd:1298:33  */
  assign n2249 = n2238 ? n2243 : div_quot;
  /* TG68K_ALU.vhd:1298:33  */
  assign n2251 = n2238 ? 1'b0 : n2248;
  /* TG68K_ALU.vhd:1311:47  */
  assign n2254 = micro_state == 7'b1010110;
  /* TG68K_ALU.vhd:1312:72  */
  assign n2255 = OP2out[31]; // extract
  /* TG68K_ALU.vhd:1312:77  */
  assign n2256 = n2255 ^ op1_sign;
  /* TG68K_ALU.vhd:1312:61  */
  assign n2257 = signedop & n2256;
  /* TG68K_ALU.vhd:1316:73  */
  assign n2258 = div_reg[63:32]; // extract
  /* TG68K_ALU.vhd:1316:65  */
  assign n2260 = {1'b0, n2258};
  /* TG68K_ALU.vhd:1316:93  */
  assign n2262 = {1'b0, op2outext};
  /* TG68K_ALU.vhd:1316:123  */
  assign n2263 = OP2out[15:0]; // extract
  /* TG68K_ALU.vhd:1316:116  */
  assign n2264 = {n2262, n2263};
  /* TG68K_ALU.vhd:1316:88  */
  assign n2265 = n2260 - n2264;
  /* TG68K_ALU.vhd:1319:40  */
  assign n2268 = exec[68]; // extract
  /* TG68K_ALU.vhd:1319:56  */
  assign n2269 = ~n2268;
  /* TG68K_ALU.vhd:1322:87  */
  assign n2270 = div_quot[63:32]; // extract
  /* TG68K_ALU.vhd:1322:78  */
  assign n2272 = 32'b00000000000000000000000000000000 - n2270;
  /* TG68K_ALU.vhd:1324:85  */
  assign n2273 = div_quot[63:32]; // extract
  /* TG68K_ALU.vhd:1321:41  */
  assign n2274 = op1_sign ? n2272 : n2273;
  assign n2275 = {n2274, result_div_pre};
  /* TG68K_ALU.vhd:1293:25  */
  assign n2277 = n2269 & clkena_lw;
  /* TG68K_ALU.vhd:1293:25  */
  assign n2278 = n2235 & clkena_lw;
  /* TG68K_ALU.vhd:1293:25  */
  assign n2280 = n2254 & clkena_lw;
  /* TG68K_ALU.vhd:1293:25  */
  assign n2281 = n2254 & clkena_lw;
  /* TG68K_ALU.vhd:1293:25  */
  assign n2284 = n2238 & clkena_lw;
  assign n2294 = {n106, n103};
  assign n2295 = {n257, n250, n243};
  assign n2296 = {n235, n234, n229, n187};
  /* TG68K_ALU.vhd:996:17  */
  always @(posedge clk)
    n2297 <= n2005;
  /* TG68K_ALU.vhd:996:17  */
  assign n2298 = {n279, n317};
  assign n2300 = {64'bZ, n2040, n2041};
  /* TG68K_ALU.vhd:1292:17  */
  assign n2301 = n2277 ? n2275 : result_div;
  /* TG68K_ALU.vhd:1292:17  */
  always @(posedge clk)
    n2302 <= n2301;
  /* TG68K_ALU.vhd:1292:17  */
  assign n2303 = n2278 ? n2229 : v_flag;
  /* TG68K_ALU.vhd:1292:17  */
  always @(posedge clk)
    n2304 <= n2303;
  /* TG68K_ALU.vhd:996:17  */
  always @(posedge clk)
    n2305 <= n2006;
  /* TG68K_ALU.vhd:405:17  */
  assign n2307 = clkena_lw ? n338 : bchg;
  /* TG68K_ALU.vhd:405:17  */
  always @(posedge clk)
    n2308 <= n2307;
  /* TG68K_ALU.vhd:405:17  */
  assign n2309 = clkena_lw ? n342 : bset;
  /* TG68K_ALU.vhd:405:17  */
  always @(posedge clk)
    n2310 <= n2309;
  assign n2312 = mulu_reg[31:0]; // extract
  /* TG68K_ALU.vhd:1211:17  */
  assign n2313 = clkena_lw ? n2071 : n2312;
  /* TG68K_ALU.vhd:1211:17  */
  always @(posedge clk)
    n2314 <= n2313;
  assign n2316 = {32'bZ, n2314};
  /* TG68K_ALU.vhd:1292:17  */
  assign n2319 = clkena_lw ? n2249 : div_reg;
  /* TG68K_ALU.vhd:1292:17  */
  always @(posedge clk)
    n2320 <= n2319;
  /* TG68K_ALU.vhd:1292:17  */
  assign n2321 = {n2204, n2207};
  /* TG68K_ALU.vhd:1292:17  */
  assign n2323 = n2280 ? n2257 : div_neg;
  /* TG68K_ALU.vhd:1292:17  */
  always @(posedge clk)
    n2324 <= n2323;
  /* TG68K_ALU.vhd:1292:17  */
  assign n2325 = n2281 ? n2265 : div_over;
  /* TG68K_ALU.vhd:1292:17  */
  always @(posedge clk)
    n2326 <= n2325;
  /* TG68K_ALU.vhd:1292:17  */
  assign n2327 = clkena_lw ? n2251 : nozero;
  /* TG68K_ALU.vhd:1292:17  */
  always @(posedge clk)
    n2328 <= n2327;
  /* TG68K_ALU.vhd:1292:17  */
  assign n2329 = {n2180, n2177, n2175};
  /* TG68K_ALU.vhd:1292:17  */
  assign n2330 = clkena_lw ? divs : signedop;
  /* TG68K_ALU.vhd:1292:17  */
  always @(posedge clk)
    n2331 <= n2330;
  /* TG68K_ALU.vhd:1292:17  */
  assign n2332 = n2284 ? n2246 : op1_sign;
  /* TG68K_ALU.vhd:1292:17  */
  always @(posedge clk)
    n2333 <= n2332;
  assign n2336 = {n793, n783, n772, n761, n750, n739, n728, n717, n706, n695, n684, n673, n662, n651, n640, n629, n618, n607, n596, n585, n574, n563, n552, n541, n530, n519, n508, n497, n486, n475, n464, n452};
  assign n2338 = {n1088, n1084, n1079, n1074, n1069, n1064, n1059, n1054, n1049, n1044, n1039, n1034, n1029, n1024, n1019, n1014, n1009, n1004, n999, n994, n989, n984, n979, n974, n969, n964, n959, n954, n949, n944, n939, n934, n929, n924, n919, n914, n909, n904, n899, n894};
  assign n2339 = {n794, n786, n775, n764, n753, n742, n731, n720, n709, n698, n687, n676, n665, n654, n643, n632, n621, n610, n599, n588, n577, n566, n555, n544, n533, n522, n511, n500, n489, n478, n467, n455};
  assign n2341 = {n850, n851};
  assign n2342 = {n1172, n1201, n1198};
  /* TG68K_ALU.vhd:446:17  */
  assign n2343 = clkena_lw ? n401 : bf_bset;
  /* TG68K_ALU.vhd:446:17  */
  always @(posedge clk)
    n2344 <= n2343;
  /* TG68K_ALU.vhd:446:17  */
  assign n2345 = clkena_lw ? n405 : bf_bchg;
  /* TG68K_ALU.vhd:446:17  */
  always @(posedge clk)
    n2346 <= n2345;
  /* TG68K_ALU.vhd:446:17  */
  assign n2347 = clkena_lw ? n409 : bf_ins;
  /* TG68K_ALU.vhd:446:17  */
  always @(posedge clk)
    n2348 <= n2347;
  /* TG68K_ALU.vhd:446:17  */
  assign n2349 = clkena_lw ? n413 : bf_exts;
  /* TG68K_ALU.vhd:446:17  */
  always @(posedge clk)
    n2350 <= n2349;
  /* TG68K_ALU.vhd:446:17  */
  assign n2351 = clkena_lw ? n417 : bf_fffo;
  /* TG68K_ALU.vhd:446:17  */
  always @(posedge clk)
    n2352 <= n2351;
  /* TG68K_ALU.vhd:446:17  */
  assign n2353 = clkena_lw ? n426 : bf_d32;
  /* TG68K_ALU.vhd:446:17  */
  always @(posedge clk)
    n2354 <= n2353;
  /* TG68K_ALU.vhd:446:17  */
  assign n2355 = clkena_lw ? n420 : bf_s32;
  /* TG68K_ALU.vhd:446:17  */
  always @(posedge clk)
    n2356 <= n2355;
  assign n2358 = {n1692, n1690, n1687, n1684, n1681, n1694};
  assign n2359 = {n1373, n1370, n1374, n1368, n1372};
  assign n2360 = {n1627, n1629};
  assign n2361 = {n1704, n1701, n1706};
  /* TG68K_ALU.vhd:446:17  */
  assign n2362 = clkena_lw ? n428 : n2363;
  /* TG68K_ALU.vhd:446:17  */
  always @(posedge clk)
    n2363 <= n2362;
  /* TG68K_ALU.vhd:996:17  */
  always @(posedge clk)
    n2364 <= n2009;
  /* TG68K_ALU.vhd:433:38  */
  assign n2365 = OP1out[bit_number * 1 +: 1]; //(Bmux)
  /* TG68K_ALU.vhd:435:17  */
  assign n2366 = bit_number[4]; // extract
  /* TG68K_ALU.vhd:435:17  */
  assign n2367 = ~n2366;
  /* TG68K_ALU.vhd:435:17  */
  assign n2368 = bit_number[3]; // extract
  /* TG68K_ALU.vhd:435:17  */
  assign n2369 = ~n2368;
  /* TG68K_ALU.vhd:435:17  */
  assign n2370 = n2367 & n2369;
  /* TG68K_ALU.vhd:435:17  */
  assign n2371 = n2367 & n2368;
  /* TG68K_ALU.vhd:435:17  */
  assign n2372 = n2366 & n2369;
  /* TG68K_ALU.vhd:435:17  */
  assign n2373 = n2366 & n2368;
  /* TG68K_ALU.vhd:435:17  */
  assign n2374 = bit_number[2]; // extract
  /* TG68K_ALU.vhd:435:17  */
  assign n2375 = ~n2374;
  /* TG68K_ALU.vhd:435:17  */
  assign n2376 = n2370 & n2375;
  /* TG68K_ALU.vhd:435:17  */
  assign n2377 = n2370 & n2374;
  /* TG68K_ALU.vhd:435:17  */
  assign n2378 = n2371 & n2375;
  /* TG68K_ALU.vhd:435:17  */
  assign n2379 = n2371 & n2374;
  /* TG68K_ALU.vhd:435:17  */
  assign n2380 = n2372 & n2375;
  /* TG68K_ALU.vhd:435:17  */
  assign n2381 = n2372 & n2374;
  /* TG68K_ALU.vhd:435:17  */
  assign n2382 = n2373 & n2375;
  /* TG68K_ALU.vhd:435:17  */
  assign n2383 = n2373 & n2374;
  /* TG68K_ALU.vhd:435:17  */
  assign n2384 = bit_number[1]; // extract
  /* TG68K_ALU.vhd:435:17  */
  assign n2385 = ~n2384;
  /* TG68K_ALU.vhd:435:17  */
  assign n2386 = n2376 & n2385;
  /* TG68K_ALU.vhd:435:17  */
  assign n2387 = n2376 & n2384;
  /* TG68K_ALU.vhd:435:17  */
  assign n2388 = n2377 & n2385;
  /* TG68K_ALU.vhd:435:17  */
  assign n2389 = n2377 & n2384;
  /* TG68K_ALU.vhd:435:17  */
  assign n2390 = n2378 & n2385;
  /* TG68K_ALU.vhd:435:17  */
  assign n2391 = n2378 & n2384;
  /* TG68K_ALU.vhd:435:17  */
  assign n2392 = n2379 & n2385;
  /* TG68K_ALU.vhd:435:17  */
  assign n2393 = n2379 & n2384;
  /* TG68K_ALU.vhd:435:17  */
  assign n2394 = n2380 & n2385;
  /* TG68K_ALU.vhd:435:17  */
  assign n2395 = n2380 & n2384;
  /* TG68K_ALU.vhd:435:17  */
  assign n2396 = n2381 & n2385;
  /* TG68K_ALU.vhd:435:17  */
  assign n2397 = n2381 & n2384;
  /* TG68K_ALU.vhd:435:17  */
  assign n2398 = n2382 & n2385;
  /* TG68K_ALU.vhd:435:17  */
  assign n2399 = n2382 & n2384;
  /* TG68K_ALU.vhd:435:17  */
  assign n2400 = n2383 & n2385;
  /* TG68K_ALU.vhd:435:17  */
  assign n2401 = n2383 & n2384;
  /* TG68K_ALU.vhd:435:17  */
  assign n2402 = bit_number[0]; // extract
  /* TG68K_ALU.vhd:435:17  */
  assign n2403 = ~n2402;
  /* TG68K_ALU.vhd:435:17  */
  assign n2404 = n2386 & n2403;
  /* TG68K_ALU.vhd:435:17  */
  assign n2405 = n2386 & n2402;
  /* TG68K_ALU.vhd:435:17  */
  assign n2406 = n2387 & n2403;
  /* TG68K_ALU.vhd:435:17  */
  assign n2407 = n2387 & n2402;
  /* TG68K_ALU.vhd:435:17  */
  assign n2408 = n2388 & n2403;
  /* TG68K_ALU.vhd:435:17  */
  assign n2409 = n2388 & n2402;
  /* TG68K_ALU.vhd:435:17  */
  assign n2410 = n2389 & n2403;
  /* TG68K_ALU.vhd:435:17  */
  assign n2411 = n2389 & n2402;
  /* TG68K_ALU.vhd:435:17  */
  assign n2412 = n2390 & n2403;
  /* TG68K_ALU.vhd:435:17  */
  assign n2413 = n2390 & n2402;
  /* TG68K_ALU.vhd:435:17  */
  assign n2414 = n2391 & n2403;
  /* TG68K_ALU.vhd:435:17  */
  assign n2415 = n2391 & n2402;
  /* TG68K_ALU.vhd:435:17  */
  assign n2416 = n2392 & n2403;
  /* TG68K_ALU.vhd:435:17  */
  assign n2417 = n2392 & n2402;
  /* TG68K_ALU.vhd:435:17  */
  assign n2418 = n2393 & n2403;
  /* TG68K_ALU.vhd:435:17  */
  assign n2419 = n2393 & n2402;
  /* TG68K_ALU.vhd:435:17  */
  assign n2420 = n2394 & n2403;
  /* TG68K_ALU.vhd:435:17  */
  assign n2421 = n2394 & n2402;
  /* TG68K_ALU.vhd:435:17  */
  assign n2422 = n2395 & n2403;
  /* TG68K_ALU.vhd:435:17  */
  assign n2423 = n2395 & n2402;
  /* TG68K_ALU.vhd:435:17  */
  assign n2424 = n2396 & n2403;
  /* TG68K_ALU.vhd:435:17  */
  assign n2425 = n2396 & n2402;
  /* TG68K_ALU.vhd:435:17  */
  assign n2426 = n2397 & n2403;
  /* TG68K_ALU.vhd:435:17  */
  assign n2427 = n2397 & n2402;
  /* TG68K_ALU.vhd:435:17  */
  assign n2428 = n2398 & n2403;
  /* TG68K_ALU.vhd:435:17  */
  assign n2429 = n2398 & n2402;
  /* TG68K_ALU.vhd:435:17  */
  assign n2430 = n2399 & n2403;
  /* TG68K_ALU.vhd:435:17  */
  assign n2431 = n2399 & n2402;
  /* TG68K_ALU.vhd:435:17  */
  assign n2432 = n2400 & n2403;
  /* TG68K_ALU.vhd:435:17  */
  assign n2433 = n2400 & n2402;
  /* TG68K_ALU.vhd:435:17  */
  assign n2434 = n2401 & n2403;
  /* TG68K_ALU.vhd:435:17  */
  assign n2435 = n2401 & n2402;
  assign n2436 = OP1out[0]; // extract
  /* TG68K_ALU.vhd:435:17  */
  assign n2437 = n2404 ? n374 : n2436;
  assign n2438 = OP1out[1]; // extract
  /* TG68K_ALU.vhd:435:17  */
  assign n2439 = n2405 ? n374 : n2438;
  assign n2440 = OP1out[2]; // extract
  /* TG68K_ALU.vhd:435:17  */
  assign n2441 = n2406 ? n374 : n2440;
  assign n2442 = OP1out[3]; // extract
  /* TG68K_ALU.vhd:435:17  */
  assign n2443 = n2407 ? n374 : n2442;
  assign n2444 = OP1out[4]; // extract
  /* TG68K_ALU.vhd:435:17  */
  assign n2445 = n2408 ? n374 : n2444;
  assign n2446 = OP1out[5]; // extract
  /* TG68K_ALU.vhd:435:17  */
  assign n2447 = n2409 ? n374 : n2446;
  assign n2448 = OP1out[6]; // extract
  /* TG68K_ALU.vhd:435:17  */
  assign n2449 = n2410 ? n374 : n2448;
  assign n2450 = OP1out[7]; // extract
  /* TG68K_ALU.vhd:435:17  */
  assign n2451 = n2411 ? n374 : n2450;
  /* TG68K_ALU.vhd:705:50  */
  assign n2452 = OP1out[8]; // extract
  /* TG68K_ALU.vhd:435:17  */
  assign n2453 = n2412 ? n374 : n2452;
  assign n2454 = OP1out[9]; // extract
  /* TG68K_ALU.vhd:435:17  */
  assign n2455 = n2413 ? n374 : n2454;
  assign n2456 = OP1out[10]; // extract
  /* TG68K_ALU.vhd:435:17  */
  assign n2457 = n2414 ? n374 : n2456;
  assign n2458 = OP1out[11]; // extract
  /* TG68K_ALU.vhd:435:17  */
  assign n2459 = n2415 ? n374 : n2458;
  /* TG68K_ALU.vhd:701:51  */
  assign n2460 = OP1out[12]; // extract
  /* TG68K_ALU.vhd:435:17  */
  assign n2461 = n2416 ? n374 : n2460;
  /* TG68K_ALU.vhd:695:63  */
  assign n2462 = OP1out[13]; // extract
  /* TG68K_ALU.vhd:435:17  */
  assign n2463 = n2417 ? n374 : n2462;
  /* TG68K_ALU.vhd:669:17  */
  assign n2464 = OP1out[14]; // extract
  /* TG68K_ALU.vhd:435:17  */
  assign n2465 = n2418 ? n374 : n2464;
  /* TG68K_ALU.vhd:669:17  */
  assign n2466 = OP1out[15]; // extract
  /* TG68K_ALU.vhd:435:17  */
  assign n2467 = n2419 ? n374 : n2466;
  assign n2468 = OP1out[16]; // extract
  /* TG68K_ALU.vhd:435:17  */
  assign n2469 = n2420 ? n374 : n2468;
  /* TG68K_ALU.vhd:679:25  */
  assign n2470 = OP1out[17]; // extract
  /* TG68K_ALU.vhd:435:17  */
  assign n2471 = n2421 ? n374 : n2470;
  /* TG68K_ALU.vhd:681:66  */
  assign n2472 = OP1out[18]; // extract
  /* TG68K_ALU.vhd:435:17  */
  assign n2473 = n2422 ? n374 : n2472;
  assign n2474 = OP1out[19]; // extract
  /* TG68K_ALU.vhd:435:17  */
  assign n2475 = n2423 ? n374 : n2474;
  /* TG68K_ALU.vhd:677:65  */
  assign n2476 = OP1out[20]; // extract
  /* TG68K_ALU.vhd:435:17  */
  assign n2477 = n2424 ? n374 : n2476;
  assign n2478 = OP1out[21]; // extract
  /* TG68K_ALU.vhd:435:17  */
  assign n2479 = n2425 ? n374 : n2478;
  assign n2480 = OP1out[22]; // extract
  /* TG68K_ALU.vhd:435:17  */
  assign n2481 = n2426 ? n374 : n2480;
  assign n2482 = OP1out[23]; // extract
  /* TG68K_ALU.vhd:435:17  */
  assign n2483 = n2427 ? n374 : n2482;
  assign n2484 = OP1out[24]; // extract
  /* TG68K_ALU.vhd:435:17  */
  assign n2485 = n2428 ? n374 : n2484;
  assign n2486 = OP1out[25]; // extract
  /* TG68K_ALU.vhd:435:17  */
  assign n2487 = n2429 ? n374 : n2486;
  assign n2488 = OP1out[26]; // extract
  /* TG68K_ALU.vhd:435:17  */
  assign n2489 = n2430 ? n374 : n2488;
  assign n2490 = OP1out[27]; // extract
  /* TG68K_ALU.vhd:435:17  */
  assign n2491 = n2431 ? n374 : n2490;
  assign n2492 = OP1out[28]; // extract
  /* TG68K_ALU.vhd:435:17  */
  assign n2493 = n2432 ? n374 : n2492;
  assign n2494 = OP1out[29]; // extract
  /* TG68K_ALU.vhd:435:17  */
  assign n2495 = n2433 ? n374 : n2494;
  assign n2496 = OP1out[30]; // extract
  /* TG68K_ALU.vhd:435:17  */
  assign n2497 = n2434 ? n374 : n2496;
  assign n2498 = OP1out[31]; // extract
  /* TG68K_ALU.vhd:435:17  */
  assign n2499 = n2435 ? n374 : n2498;
  assign n2500 = {n2499, n2497, n2495, n2493, n2491, n2489, n2487, n2485, n2483, n2481, n2479, n2477, n2475, n2473, n2471, n2469, n2467, n2465, n2463, n2461, n2459, n2457, n2455, n2453, n2451, n2449, n2447, n2445, n2443, n2441, n2439, n2437};
  /* TG68K_ALU.vhd:496:37  */
  assign n2501 = datareg[n796 * 1 +: 1]; //(Bmux)
  /* TG68K_ALU.vhd:761:17  */
  assign n2502 = bit_msb[5]; // extract
  /* TG68K_ALU.vhd:761:17  */
  assign n2503 = ~n2502;
  /* TG68K_ALU.vhd:761:17  */
  assign n2504 = bit_msb[4]; // extract
  /* TG68K_ALU.vhd:761:17  */
  assign n2505 = ~n2504;
  /* TG68K_ALU.vhd:761:17  */
  assign n2506 = n2503 & n2505;
  /* TG68K_ALU.vhd:761:17  */
  assign n2507 = n2503 & n2504;
  /* TG68K_ALU.vhd:761:17  */
  assign n2508 = n2502 & n2505;
  /* TG68K_ALU.vhd:761:17  */
  assign n2509 = bit_msb[3]; // extract
  /* TG68K_ALU.vhd:761:17  */
  assign n2510 = ~n2509;
  /* TG68K_ALU.vhd:761:17  */
  assign n2511 = n2506 & n2510;
  /* TG68K_ALU.vhd:761:17  */
  assign n2512 = n2506 & n2509;
  /* TG68K_ALU.vhd:761:17  */
  assign n2513 = n2507 & n2510;
  /* TG68K_ALU.vhd:761:17  */
  assign n2514 = n2507 & n2509;
  /* TG68K_ALU.vhd:761:17  */
  assign n2515 = n2508 & n2510;
  /* TG68K_ALU.vhd:761:17  */
  assign n2516 = bit_msb[2]; // extract
  /* TG68K_ALU.vhd:761:17  */
  assign n2517 = ~n2516;
  /* TG68K_ALU.vhd:761:17  */
  assign n2518 = n2511 & n2517;
  /* TG68K_ALU.vhd:761:17  */
  assign n2519 = n2511 & n2516;
  /* TG68K_ALU.vhd:761:17  */
  assign n2520 = n2512 & n2517;
  /* TG68K_ALU.vhd:761:17  */
  assign n2521 = n2512 & n2516;
  /* TG68K_ALU.vhd:761:17  */
  assign n2522 = n2513 & n2517;
  /* TG68K_ALU.vhd:761:17  */
  assign n2523 = n2513 & n2516;
  /* TG68K_ALU.vhd:761:17  */
  assign n2524 = n2514 & n2517;
  /* TG68K_ALU.vhd:761:17  */
  assign n2525 = n2514 & n2516;
  /* TG68K_ALU.vhd:761:17  */
  assign n2526 = n2515 & n2517;
  /* TG68K_ALU.vhd:761:17  */
  assign n2527 = bit_msb[1]; // extract
  /* TG68K_ALU.vhd:761:17  */
  assign n2528 = ~n2527;
  /* TG68K_ALU.vhd:761:17  */
  assign n2529 = n2518 & n2528;
  /* TG68K_ALU.vhd:761:17  */
  assign n2530 = n2518 & n2527;
  /* TG68K_ALU.vhd:761:17  */
  assign n2531 = n2519 & n2528;
  /* TG68K_ALU.vhd:761:17  */
  assign n2532 = n2519 & n2527;
  /* TG68K_ALU.vhd:761:17  */
  assign n2533 = n2520 & n2528;
  /* TG68K_ALU.vhd:761:17  */
  assign n2534 = n2520 & n2527;
  /* TG68K_ALU.vhd:761:17  */
  assign n2535 = n2521 & n2528;
  /* TG68K_ALU.vhd:761:17  */
  assign n2536 = n2521 & n2527;
  /* TG68K_ALU.vhd:761:17  */
  assign n2537 = n2522 & n2528;
  /* TG68K_ALU.vhd:761:17  */
  assign n2538 = n2522 & n2527;
  /* TG68K_ALU.vhd:761:17  */
  assign n2539 = n2523 & n2528;
  /* TG68K_ALU.vhd:761:17  */
  assign n2540 = n2523 & n2527;
  /* TG68K_ALU.vhd:761:17  */
  assign n2541 = n2524 & n2528;
  /* TG68K_ALU.vhd:761:17  */
  assign n2542 = n2524 & n2527;
  /* TG68K_ALU.vhd:761:17  */
  assign n2543 = n2525 & n2528;
  /* TG68K_ALU.vhd:761:17  */
  assign n2544 = n2525 & n2527;
  /* TG68K_ALU.vhd:761:17  */
  assign n2545 = n2526 & n2528;
  /* TG68K_ALU.vhd:761:17  */
  assign n2546 = bit_msb[0]; // extract
  /* TG68K_ALU.vhd:761:17  */
  assign n2547 = ~n2546;
  /* TG68K_ALU.vhd:761:17  */
  assign n2548 = n2529 & n2547;
  /* TG68K_ALU.vhd:761:17  */
  assign n2549 = n2529 & n2546;
  /* TG68K_ALU.vhd:761:17  */
  assign n2550 = n2530 & n2547;
  /* TG68K_ALU.vhd:761:17  */
  assign n2551 = n2530 & n2546;
  /* TG68K_ALU.vhd:761:17  */
  assign n2552 = n2531 & n2547;
  /* TG68K_ALU.vhd:761:17  */
  assign n2553 = n2531 & n2546;
  /* TG68K_ALU.vhd:761:17  */
  assign n2554 = n2532 & n2547;
  /* TG68K_ALU.vhd:761:17  */
  assign n2555 = n2532 & n2546;
  /* TG68K_ALU.vhd:761:17  */
  assign n2556 = n2533 & n2547;
  /* TG68K_ALU.vhd:761:17  */
  assign n2557 = n2533 & n2546;
  /* TG68K_ALU.vhd:761:17  */
  assign n2558 = n2534 & n2547;
  /* TG68K_ALU.vhd:761:17  */
  assign n2559 = n2534 & n2546;
  /* TG68K_ALU.vhd:761:17  */
  assign n2560 = n2535 & n2547;
  /* TG68K_ALU.vhd:761:17  */
  assign n2561 = n2535 & n2546;
  /* TG68K_ALU.vhd:761:17  */
  assign n2562 = n2536 & n2547;
  /* TG68K_ALU.vhd:761:17  */
  assign n2563 = n2536 & n2546;
  /* TG68K_ALU.vhd:761:17  */
  assign n2564 = n2537 & n2547;
  /* TG68K_ALU.vhd:761:17  */
  assign n2565 = n2537 & n2546;
  /* TG68K_ALU.vhd:761:17  */
  assign n2566 = n2538 & n2547;
  /* TG68K_ALU.vhd:761:17  */
  assign n2567 = n2538 & n2546;
  /* TG68K_ALU.vhd:761:17  */
  assign n2568 = n2539 & n2547;
  /* TG68K_ALU.vhd:761:17  */
  assign n2569 = n2539 & n2546;
  /* TG68K_ALU.vhd:761:17  */
  assign n2570 = n2540 & n2547;
  /* TG68K_ALU.vhd:761:17  */
  assign n2571 = n2540 & n2546;
  /* TG68K_ALU.vhd:761:17  */
  assign n2572 = n2541 & n2547;
  /* TG68K_ALU.vhd:761:17  */
  assign n2573 = n2541 & n2546;
  /* TG68K_ALU.vhd:761:17  */
  assign n2574 = n2542 & n2547;
  /* TG68K_ALU.vhd:761:17  */
  assign n2575 = n2542 & n2546;
  /* TG68K_ALU.vhd:761:17  */
  assign n2576 = n2543 & n2547;
  /* TG68K_ALU.vhd:761:17  */
  assign n2577 = n2543 & n2546;
  /* TG68K_ALU.vhd:761:17  */
  assign n2578 = n2544 & n2547;
  /* TG68K_ALU.vhd:761:17  */
  assign n2579 = n2544 & n2546;
  /* TG68K_ALU.vhd:761:17  */
  assign n2580 = n2545 & n2547;
  /* TG68K_ALU.vhd:761:17  */
  assign n2581 = n2545 & n2546;
  assign n2582 = n1339[0]; // extract
  /* TG68K_ALU.vhd:761:17  */
  assign n2583 = n2548 ? 1'b1 : n2582;
  assign n2584 = n1339[1]; // extract
  /* TG68K_ALU.vhd:761:17  */
  assign n2585 = n2549 ? 1'b1 : n2584;
  assign n2586 = n1339[2]; // extract
  /* TG68K_ALU.vhd:761:17  */
  assign n2587 = n2550 ? 1'b1 : n2586;
  assign n2588 = n1339[3]; // extract
  /* TG68K_ALU.vhd:761:17  */
  assign n2589 = n2551 ? 1'b1 : n2588;
  /* TG68K_ALU.vhd:446:17  */
  assign n2590 = n1339[4]; // extract
  /* TG68K_ALU.vhd:761:17  */
  assign n2591 = n2552 ? 1'b1 : n2590;
  /* TG68K_ALU.vhd:446:17  */
  assign n2592 = n1339[5]; // extract
  /* TG68K_ALU.vhd:761:17  */
  assign n2593 = n2553 ? 1'b1 : n2592;
  /* TG68K_ALU.vhd:446:17  */
  assign n2594 = n1339[6]; // extract
  /* TG68K_ALU.vhd:761:17  */
  assign n2595 = n2554 ? 1'b1 : n2594;
  /* TG68K_ALU.vhd:446:17  */
  assign n2596 = n1339[7]; // extract
  /* TG68K_ALU.vhd:761:17  */
  assign n2597 = n2555 ? 1'b1 : n2596;
  assign n2598 = n1339[8]; // extract
  /* TG68K_ALU.vhd:761:17  */
  assign n2599 = n2556 ? 1'b1 : n2598;
  assign n2600 = n1339[9]; // extract
  /* TG68K_ALU.vhd:761:17  */
  assign n2601 = n2557 ? 1'b1 : n2600;
  assign n2602 = n1339[10]; // extract
  /* TG68K_ALU.vhd:761:17  */
  assign n2603 = n2558 ? 1'b1 : n2602;
  /* TG68K_ALU.vhd:442:1  */
  assign n2604 = n1339[11]; // extract
  /* TG68K_ALU.vhd:761:17  */
  assign n2605 = n2559 ? 1'b1 : n2604;
  /* TG68K_ALU.vhd:435:26  */
  assign n2606 = n1339[12]; // extract
  /* TG68K_ALU.vhd:761:17  */
  assign n2607 = n2560 ? 1'b1 : n2606;
  /* TG68K_ALU.vhd:405:17  */
  assign n2608 = n1339[13]; // extract
  /* TG68K_ALU.vhd:761:17  */
  assign n2609 = n2561 ? 1'b1 : n2608;
  assign n2610 = n1339[14]; // extract
  /* TG68K_ALU.vhd:761:17  */
  assign n2611 = n2562 ? 1'b1 : n2610;
  /* TG68K_ALU.vhd:403:1  */
  assign n2612 = n1339[15]; // extract
  /* TG68K_ALU.vhd:761:17  */
  assign n2613 = n2563 ? 1'b1 : n2612;
  assign n2614 = n1339[16]; // extract
  /* TG68K_ALU.vhd:761:17  */
  assign n2615 = n2564 ? 1'b1 : n2614;
  assign n2616 = n1339[17]; // extract
  /* TG68K_ALU.vhd:761:17  */
  assign n2617 = n2565 ? 1'b1 : n2616;
  /* TG68K_ALU.vhd:289:1  */
  assign n2618 = n1339[18]; // extract
  /* TG68K_ALU.vhd:761:17  */
  assign n2619 = n2566 ? 1'b1 : n2618;
  assign n2620 = n1339[19]; // extract
  /* TG68K_ALU.vhd:761:17  */
  assign n2621 = n2567 ? 1'b1 : n2620;
  /* TG68K_ALU.vhd:182:16  */
  assign n2622 = n1339[20]; // extract
  /* TG68K_ALU.vhd:761:17  */
  assign n2623 = n2568 ? 1'b1 : n2622;
  /* TG68K_ALU.vhd:152:16  */
  assign n2624 = n1339[21]; // extract
  /* TG68K_ALU.vhd:761:17  */
  assign n2625 = n2569 ? 1'b1 : n2624;
  /* TG68K_ALU.vhd:147:16  */
  assign n2626 = n1339[22]; // extract
  /* TG68K_ALU.vhd:761:17  */
  assign n2627 = n2570 ? 1'b1 : n2626;
  /* TG68K_ALU.vhd:131:16  */
  assign n2628 = n1339[23]; // extract
  /* TG68K_ALU.vhd:761:17  */
  assign n2629 = n2571 ? 1'b1 : n2628;
  /* TG68K_ALU.vhd:119:16  */
  assign n2630 = n1339[24]; // extract
  /* TG68K_ALU.vhd:761:17  */
  assign n2631 = n2572 ? 1'b1 : n2630;
  /* TG68K_ALU.vhd:113:16  */
  assign n2632 = n1339[25]; // extract
  /* TG68K_ALU.vhd:761:17  */
  assign n2633 = n2573 ? 1'b1 : n2632;
  /* TG68K_ALU.vhd:996:17  */
  assign n2634 = n1339[26]; // extract
  /* TG68K_ALU.vhd:761:17  */
  assign n2635 = n2574 ? 1'b1 : n2634;
  assign n2636 = n1339[27]; // extract
  /* TG68K_ALU.vhd:761:17  */
  assign n2637 = n2575 ? 1'b1 : n2636;
  assign n2638 = n1339[28]; // extract
  /* TG68K_ALU.vhd:761:17  */
  assign n2639 = n2576 ? 1'b1 : n2638;
  assign n2640 = n1339[29]; // extract
  /* TG68K_ALU.vhd:761:17  */
  assign n2641 = n2577 ? 1'b1 : n2640;
  assign n2642 = n1339[30]; // extract
  /* TG68K_ALU.vhd:761:17  */
  assign n2643 = n2578 ? 1'b1 : n2642;
  assign n2644 = n1339[31]; // extract
  /* TG68K_ALU.vhd:761:17  */
  assign n2645 = n2579 ? 1'b1 : n2644;
  assign n2646 = n1339[32]; // extract
  /* TG68K_ALU.vhd:761:17  */
  assign n2647 = n2580 ? 1'b1 : n2646;
  assign n2648 = n1339[33]; // extract
  /* TG68K_ALU.vhd:761:17  */
  assign n2649 = n2581 ? 1'b1 : n2648;
  assign n2650 = {n2649, n2647, n2645, n2643, n2641, n2639, n2637, n2635, n2633, n2631, n2629, n2627, n2625, n2623, n2621, n2619, n2617, n2615, n2613, n2611, n2609, n2607, n2605, n2603, n2601, n2599, n2597, n2595, n2593, n2591, n2589, n2587, n2585, n2583};
endmodule

