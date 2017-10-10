open HolKernel Parse
open testutils

open bir_inst_liftingLib;
open bmil_arm8
open PPBackEnd Parse

(* Tests for ARM 8 *)

val _ = Parse.current_backend := PPBackEnd.vt100_terminal;

(* style for success, fail and header *)
val sty_OK     = [FG Green];
val sty_CACHE  = [FG Yellow];
val sty_FAIL   = [FG OrangeRed];
val sty_HEADER = [Bold, Underline];

(*
For manual testing

val _ = Parse.current_backend := PPBackEnd.emacs_terminal;

val mu_b = Arbnum.fromInt 0;
val mu_e = Arbnum.fromInt 0x1000000;
val pc = Arbnum.fromInt 0x10030;
val hex_code = "12001C00"
*)

(* run a single instruction "hexcode" given a region of memory
   and a PC. Some debug output is printed and the required runtime
   is measured. The result is a triple:

   - res : thm option ---
       the theorem produced, NONE is something went wrong
   - ed  : bir_inst_liftingExn_data option ---
       a description of what went wrong, if available
   - d_s : string ---
       time in seconds as a string

   We also keep track of all failed hex_codes in a references
   "failed_hexcodes_list".
*)

val failed_hexcodes_list = ref ([]:(string * bir_inst_liftingExn_data option) list);
val success_hexcodes_list = ref ([]: (string * thm) list);
fun lift_instr_cached mu_thms cache pc hex_code = let
  val _ = print (hex_code ^ " @ 0x" ^ (Arbnum.toHexString pc));
  val timer = (Time.now())
  val (res, ed) = (SOME (bir_lift_instr_mu mu_thms cache pc hex_code), NONE) handle
                   bir_inst_liftingExn (_, d)  => (NONE, SOME d)
                 | HOL_ERR _ => (NONE, NONE);

  val d_time = Time.- (Time.now(), timer);
  val d_s = (Time.toString d_time);

  val _ = print (" - " ^ d_s ^ " s - ");
  val (res', cache') = case res of
             SOME (thm, cache', _) => ((SOME thm), cache')
           | NONE => (NONE, cache)
  val _ = case res of
             SOME (thm, _, cache_used) =>
                 (success_hexcodes_list := (hex_code, thm)::(!success_hexcodes_list);
                 (print_with_style sty_OK "OK");
                 (if cache_used then (print " - "; print_with_style sty_CACHE "cached") else ());
                 (print "\n"))
           | NONE =>
             (failed_hexcodes_list := (hex_code, ed)::(!failed_hexcodes_list);
             (print_with_style sty_FAIL "FAILED\n"));
  val _ = case ed of
      NONE => ()
    | SOME d => (let
        val s = ("   "^(bir_inst_liftingExn_data_to_string d) ^ "\n");
      in print_with_style sty_FAIL s end)
in
  (res', ed, d_s, cache')
end;

fun lift_instr mu_b mu_e pc hex_code = let
  val mu_thms = bir_lift_instr_prepare_mu_thms (mu_b, mu_e)
  val (res, ed, d_s, _) = lift_instr_cached mu_thms lift_inst_cache_empty pc hex_code
in
  (res, ed, d_s)
end;

fun hex_code_of_asm asm = hd (arm8AssemblerLib.arm8_code asm)

fun lift_instr_asm mu_b mu_e pc asm =
  lift_instr mu_b mu_e pc (hex_code_of_asm asm);

(* And a list version *)

fun lift_instr_list mu_b mu_e pc hex_codes = let
  val timer = (Time.now())
  val len_codes = (length hex_codes);

  val _ = print ("running " ^ (Int.toString (len_codes)) ^ " instrutions; first pc 0x" ^
              (Arbnum.toHexString pc) ^ "\n\n");

  val mu_thms = bir_lift_instr_prepare_mu_thms (mu_b, mu_e)

  fun run_inst (i, (c, pc, res, cache)) = let
    val _ = print ((Int.toString c) ^ "/" ^ (Int.toString (length hex_codes)) ^ ": ");
    val (r', ed, d_s, cache') = lift_instr_cached mu_thms cache pc i
    val c' = c+1;
    val pc' = Arbnum.+ (pc, Arbnum.fromInt 8);
    val r = (r', ed, d_s);
  in (c+1, pc', r::res, cache') end

  val (_, _, resL, _) = foldl run_inst (1, pc, [], lift_inst_cache_empty) hex_codes

  val d_time = Time.- (Time.now(), timer);
  val d_s = (Time.toString d_time);
  val success_c = foldl (fn ((res, _, _), c) =>
       if (is_some res) then c+1 else c) 0 resL
  val fail_c = len_codes - success_c

  val _ = print "\n";
  val _ = print ("Instructions OK    : " ^ (Int.toString success_c) ^ "\n");
  val _ = print ("Instructions FAILED: " ^ (Int.toString fail_c) ^ "\n");

  val _ = print ("Time needed        : " ^ d_s ^ " s\n\n");
in
  (fail_c, success_c, resL)
end;


fun final_results expected_failed_hexcodes = let
  val _ = print_with_style sty_HEADER "\n\n\nSUMMARY FAILING HEXCODES\n\n";
  val _ = print "\n";
  val failing_l = op_mk_set (fn x => fn y => (fst x = fst y)) (!failed_hexcodes_list)
  val ok_l = op_mk_set (fn x => fn y => (fst x = fst y)) (!success_hexcodes_list)

  (* look for freshly failing ones *)
  val failing_l' = map (fn (hc, edo) =>
     (hc, edo, not (Lib.mem hc expected_failed_hexcodes))) failing_l;
  val fixed_l = List.filter (fn hc => List.exists (fn e => fst e = hc) ok_l) expected_failed_hexcodes

  (* Show all failing instructions and format them such that they can be copied
     in the code of selftest.sml
     as content of list expected_failed_hexcodes *)
  val _ = print ("Instructions FAILED: " ^ (Int.toString (length failing_l)) ^ "/" ^
         (Int.toString (length failing_l + length ok_l)) ^ "\n\n");

  fun print_failed [] = ()
    | print_failed ((hex_code, ed_opt, broken)::l) =
  let
    (* print the ones that failed, but were not excepted to in red *)
    val st = if broken then sty_FAIL else [];
    val _ = print "   ";
    val _ = print_with_style st ("\""^hex_code^"\"");
    val _ = case ed_opt of
        NONE => ()
      | SOME d => (let
          val s = (" (* "^(bir_inst_liftingExn_data_to_string d) ^ " *)");
          in print_with_style st s end);
  in if List.null l then (print "\n]\n\n") else
         (print ",\n"; print_failed l)
  end;
  val _ = if List.null failing_l' then () else (print "[\n"; print_failed failing_l');


  (* Show the hex-codes that were expected to fail, but succeeded. These
     are the ones fixed by recent changes. *)
  val _ = print ("Instructions FIXED: " ^ (Int.toString (length fixed_l)) ^ "\n\n");
  val _ = List.map (fn s => print_with_style sty_OK ("   " ^ s ^"\n")) fixed_l;
  val _ = print "\n\n";

  (* Show the hex-codes that were expected to succeed, but failed. These
     are the ones broken by recent changes. *)
  val broken_l = List.filter (fn (hc, edo, br) => br) failing_l';
  val _ = print ("Instructions BROKEN: " ^ (Int.toString (List.length broken_l)) ^ "\n\n");
  val _ = List.map (fn (hc, _, _) => print_with_style sty_FAIL ("   " ^ hc ^"\n")) broken_l;
  val _ = print "\n\n";

in
  ()
end;




(*********************)
(* SOME MANUAL TESTS *)
(*********************)

val mu_b = Arbnum.fromInt 0;
val mu_e = Arbnum.fromInt 0x1000000;
val pc = Arbnum.fromInt 0x10030;
val test_asm = lift_instr_asm mu_b mu_e pc
val test_hex = lift_instr mu_b mu_e pc

val res = print_with_style sty_HEADER "\nMANUAL TESTS\n\n";
val res = test_asm `add x0, x1, x2`;
val res = test_asm `add x1, x1, x1`;
val res = test_asm `adds x0, x1, x2`;
val res = test_asm `add x0, x0, x2`;
val res = test_asm `sub x0, x1, x2`;
val res = test_asm `mul x0, x1, x2`;
val res = test_asm `mul w0, w1, w1`;
val res = test_asm `cmp w0, #0`;
val res = test_asm `cmn w0, #0`;
val res = test_asm `cmn w0, w1`;
val res = test_asm `cmn x0, x9`;
val res = test_asm `ret`;
val res = test_asm `adds x0, x2, #8`;
val res = test_asm `subs x0, x2, #8`;
val res = test_asm `adds x0, x1, x2`;
val res = test_asm `add x0, x0, x2`;
val res = test_asm `sub x0, x1, x2`;
val res = test_asm `add x4, SP, #8`;
val res = test_asm `add x4, SP, #8`;
val res = test_asm `adds x1, x1, #0`;
val res = test_asm `lsr x1, x2, #5`;
val res = test_asm `lsr x1, x2, #0`;
val res = test_asm `lsr x1, x1, #0`;
val res = test_asm `lsr x1, x2, x3`;
val res = test_asm `lsl x1, x2, #5`;
val res = test_asm `lsl x1, x2, #0`;
val res = test_asm `lsl x1, x1, #0`;
val res = test_asm `lsl x1, x2, x3`;
val res = test_asm `asr x1, x2, #5`;
val res = test_asm `asr x1, x2, #0`;
val res = test_asm `asr x1, x1, #0`;
val res = test_asm `asr x1, x2, x3`;
val res = test_asm `ldr x0, [x2, #0]`;

  (* THERE ARE STILL MANY TODOs !!! *)
val res = test_asm `lsl x0, x2, #8`;
val res = test_asm `lsr x0, x2, #8`;
val res = test_asm `str x0, [x2, #8]`;

  (* some instructions I din't see in this file *)
(*  4003a0:     d61f0220        br      x17 *)
val res = test_asm `br  x17`;
(*  4003a4:     d503201f        nop *)
val res = test_asm `nop`;
(*  400510:     d63f0020        blr     x1 *)
val res = test_asm `blr x1`;
(*  400430:     b4000040        cbz     x0, 400438 <call_weak_fn+0x10> *)
val res = test_hex "B4000040";
(*  4004cc:     35000080        cbnz    w0, 4004dc <__do_global_dtors_aux+0x24> *)
val res = test_hex "35000080";

  (* another one, load with lsl, decode error *)
(*  4005f8:	b8617801        ldr	w1, [x0,x1,lsl #2] *)
val res = test_hex "b8617801";






(***************)
(* AES_EXAMPLE *)
(***************)

(* Test it with the instructions from aes example *)
val instrs = [
  "D101C3FF","F9000FE0","B90017E1","F90007E2","F90003E3","B94017E0","51000400",
  "B9004FE0","F94007E0","B9400000","B9002FE0","F94007E0","B9400400","B90033E0",
  "F94007E0","B9400800","B90037E0","F94007E0","B9400C00","B9003BE0","F9400FE0",
  "B9400000","B9402FE1","4A000020","B9002FE0","F9400FE0","91001000","B9400000",
  "B94033E1","4A000020","B90033E0","F9400FE0","91002000","B9400000","B94037E1",
  "4A000020","B90037E0","F9400FE0","91003000","B9400000","B9403BE1","4A000020",
  "B9003BE0","F9400FE0","91004000","F9000FE0","140000E6","B9402FE0","53187C00",
  "B90053E0","B94033E0","53107C00","12001C00","B90057E0","B94037E0","53087C00",
  "12001C00","B9005BE0","B9403BE0","12001C00","B9005FE0","B94053E0","D37EF401",
  "90000000","91394000","8B000020","B9400000","B90063E0","B94057E0","D37EF401",
  "B0000000","91094000","8B000020","B9400000","B90067E0","B9405BE0","D37EF401",
  "B0000000","91194000","8B000020","B9400000","B9006BE0","B9405FE0","D37EF401",
  "B0000000","91294000","8B000020","B9400000","B9006FE0","B94063E1","B94067E0",
  "4A000021","B9406BE0","4A000021","B9406FE0","4A000021","F9400FE0","B9400000",
  "4A000020","B9003FE0","B94033E0","53187C00","B90053E0","B94037E0","53107C00",
  "12001C00","B90057E0","B9403BE0","53087C00","12001C00","B9005BE0","B9402FE0",
  "12001C00","B9005FE0","B94053E0","D37EF401","90000000","91394000","8B000020",
  "B9400000","B90063E0","B94057E0","D37EF401","B0000000","91094000","8B000020",
  "B9400000","B90067E0","B9405BE0","D37EF401","B0000000","91194000","8B000020",
  "B9400000","B9006BE0","B9405FE0","D37EF401","B0000000","91294000","8B000020",
  "B9400000","B9006FE0","B94063E1","B94067E0","4A000021","B9406BE0","4A000021",
  "B9406FE0","4A000021","F9400FE0","91001000","B9400000","4A000020","B90043E0",
  "B94037E0","53187C00","B90053E0","B9403BE0","53107C00","12001C00","B90057E0",
  "B9402FE0","53087C00","12001C00","B9005BE0","B94033E0","12001C00","B9005FE0",
  "B94053E0","D37EF401","90000000","91394000","8B000020","B9400000","B90063E0",
  "B94057E0","D37EF401","B0000000","91094000","8B000020","B9400000","B90067E0",
  "B9405BE0","D37EF401","B0000000","91194000","8B000020","B9400000","B9006BE0",
  "B9405FE0","D37EF401","B0000000","91294000","8B000020","B9400000","B9006FE0",
  "B94063E1","B94067E0","4A000021","B9406BE0","4A000021","B9406FE0","4A000021",
  "F9400FE0","91002000","B9400000","4A000020","B90047E0","B9403BE0","53187C00",
  "B90053E0","B9402FE0","53107C00","12001C00","B90057E0","B94033E0","53087C00",
  "12001C00","B9005BE0","B94037E0","12001C00","B9005FE0","B94053E0","D37EF401",
  "90000000","91394000","8B000020","B9400000","B90063E0","B94057E0","D37EF401",
  "B0000000","91094000","8B000020","B9400000","B90067E0","B9405BE0","D37EF401",
  "B0000000","91194000","8B000020","B9400000","B9006BE0","B9405FE0","D37EF401",
  "B0000000","91294000","8B000020","B9400000","B9006FE0","B94063E1","B94067E0",
  "4A000021","B9406BE0","4A000021","B9406FE0","4A000021","F9400FE0","91003000",
  "B9400000","4A000020","B9004BE0","B9403FE0","B9002FE0","B94043E0","B90033E0",
  "B94047E0","B90037E0","B9404BE0","B9003BE0","F9400FE0","91004000","F9000FE0",
  "B9404FE0","51000400","B9004FE0","B9404FE0","7100001F","54FFE321","B9403FE0",
  "53187C00","B90053E0","B94043E0","53107C00","12001C00","B90057E0","B94047E0",
  "53087C00","12001C00","B9005BE0","B9404BE0","12001C00","B9005FE0","B94053E0",
  "D37EF401","B0000000","91194000","8B000020","B9400000","B90063E0","B94057E0",
  "D37EF401","B0000000","91294000","8B000020","B9400000","B90067E0","B9405BE0",
  "D37EF401","90000000","91394000","8B000020","B9400000","B9006BE0","B9405FE0",
  "D37EF401","B0000000","91094000","8B000020","B9400000","B9006FE0","B94063E0",
  "12081C01","B94067E0","12101C00","4A000021","B9406BE0","12181C00","4A000021",
  "B9406FE0","12001C00","4A000021","F9400FE0","B9400000","4A000020","B9002FE0",
  "B94043E0","53187C00","B90053E0","B94047E0","53107C00","12001C00","B90057E0",
  "B9404BE0","53087C00","12001C00","B9005BE0","B9403FE0","12001C00","B9005FE0",
  "B94053E0","D37EF401","B0000000","91194000","8B000020","B9400000","B90063E0",
  "B94057E0","D37EF401","B0000000","91294000","8B000020","B9400000","B90067E0",
  "B9405BE0","D37EF401","90000000","91394000","8B000020","B9400000","B9006BE0",
  "B9405FE0","D37EF401","B0000000","91094000","8B000020","B9400000","B9006FE0",
  "B94063E0","12081C01","B94067E0","12101C00","4A000021","B9406BE0","12181C00",
  "4A000021","B9406FE0","12001C00","4A000021","F9400FE0","91001000","B9400000",
  "4A000020","B90033E0","B94047E0","53187C00","B90053E0","B9404BE0","53107C00",
  "12001C00","B90057E0","B9403FE0","53087C00","12001C00","B9005BE0","B94043E0",
  "12001C00","B9005FE0","B94053E0","D37EF401","B0000000","91194000","8B000020",
  "B9400000","B90063E0","B94057E0","D37EF401","B0000000","91294000","8B000020",
  "B9400000","B90067E0","B9405BE0","D37EF401","90000000","91394000","8B000020",
  "B9400000","B9006BE0","B9405FE0","D37EF401","B0000000","91094000","8B000020",
  "B9400000","B9006FE0","B94063E0","12081C01","B94067E0","12101C00","4A000021",
  "B9406BE0","12181C00","4A000021","B9406FE0","12001C00","4A000021","F9400FE0",
  "91002000","B9400000","4A000020","B90037E0","B9404BE0","53187C00","B90053E0",
  "B9403FE0","53107C00","12001C00","B90057E0","B94043E0","53087C00","12001C00",
  "B9005BE0","B94047E0","12001C00","B9005FE0","B94053E0","D37EF401","B0000000",
  "91194000","8B000020","B9400000","B90063E0","B94057E0","D37EF401","B0000000",
  "91294000","8B000020","B9400000","B90067E0","B9405BE0","D37EF401","90000000",
  "91394000","8B000020","B9400000","B9006BE0","B9405FE0","D37EF401","B0000000",
  "91094000","8B000020","B9400000","B9006FE0","B94063E0","12081C01","B94067E0",
  "12101C00","4A000021","B9406BE0","12181C00","4A000021","B9406FE0","12001C00",
  "4A000021","F9400FE0","91003000","B9400000","4A000020","B9003BE0","F94003E0",
  "B9402FE1","B9000001","F94003E0","91001000","B94033E1","B9000001","F94003E0",
  "91002000","B94037E1","B9000001","F94003E0","91003000","B9403BE1","B9000001",
  "D503201F","9101C3FF","D65F03C0"
];


val _ = print_with_style sty_HEADER "\n\n\nTESTING AES CODE\n\n";
val _ = lift_instr_list (Arbnum.fromInt 0) (Arbnum.fromInt 0x1000000) (Arbnum.fromInt 0x400570)
    instrs






(***************)
(* AES_EXAMPLE_WITH_FUNNY_INSTRUCTIONS *)
(***************)

(* Test it with the instructions from aes example *)
val instrs = [
  "D10143FF","F9000FE0","B90017E1","F90007E2","F90003E3","B94017E0","51000400",
  "B9002FE0","F94007E0","B9400000","B9004FE0","F94007E0","B9400400","B9004BE0",
  "F94007E0","B9400800","B90047E0","F94007E0","B9400C00","B90043E0","F9400FE0",
  "B9400000","B9404FE1","4A000020","B9004FE0","F9400FE0","91001000","B9400000",
  "B9404BE1","4A000020","B9004BE0","F9400FE0","91002000","B9400000","B94047E1",
  "4A000020","B90047E0","F9400FE0","91003000","B9400000","B94043E1","4A000020",
  "B90043E0","F9400FE0","91004000","F9000FE0","140000B6","B9404FE0","53187C00",
  "53001C00","2A0003E1","90000000","9131E000","2A0103E1","B8617801","B9404BE0",
  "53107C00","53001C00","2A0003E2","90000000","9131E000","2A0203E2","91040042",
  "B8627800","4A000021","B94047E0","53087C00","53001C00","2A0003E2","90000000",
  "9131E000","2A0203E2","91080042","B8627800","4A000021","B94043E0","53001C00",
  "2A0003E2","90000000","9131E000","2A0203E2","910C0042","B8627800","4A000021",
  "F9400FE0","B9400000","4A000020","B9003FE0","B9404BE0","53187C00","53001C00",
  "2A0003E1","90000000","9131E000","2A0103E1","B8617801","B94047E0","53107C00",
  "53001C00","2A0003E2","90000000","9131E000","2A0203E2","91040042","B8627800",
  "4A000021","B94043E0","53087C00","53001C00","2A0003E2","90000000","9131E000",
  "2A0203E2","91080042","B8627800","4A000021","B9404FE0","53001C00","2A0003E2",
  "90000000","9131E000","2A0203E2","910C0042","B8627800","4A000021","F9400FE0",
  "91001000","B9400000","4A000020","B9003BE0","B94047E0","53187C00","53001C00",
  "2A0003E1","90000000","9131E000","2A0103E1","B8617801","B94043E0","53107C00",
  "53001C00","2A0003E2","90000000","9131E000","2A0203E2","91040042","B8627800",
  "4A000021","B9404FE0","53087C00","53001C00","2A0003E2","90000000","9131E000",
  "2A0203E2","91080042","B8627800","4A000021","B9404BE0","53001C00","2A0003E2",
  "90000000","9131E000","2A0203E2","910C0042","B8627800","4A000021","F9400FE0",
  "91002000","B9400000","4A000020","B90037E0","B94043E0","53187C00","53001C00",
  "2A0003E1","90000000","9131E000","2A0103E1","B8617801","B9404FE0","53107C00",
  "53001C00","2A0003E2","90000000","9131E000","2A0203E2","91040042","B8627800",
  "4A000021","B9404BE0","53087C00","53001C00","2A0003E2","90000000","9131E000",
  "2A0203E2","91080042","B8627800","4A000021","B94047E0","53001C00","2A0003E2",
  "90000000","9131E000","2A0203E2","910C0042","B8627800","4A000021","F9400FE0",
  "91003000","B9400000","4A000020","B90033E0","B9403FE0","B9004FE0","B9403BE0",
  "B9004BE0","B94037E0","B90047E0","B94033E0","B90043E0","F9400FE0","91004000",
  "F9000FE0","B9402FE0","51000400","B9002FE0","B9402FE0","6B1F001F","54FFE921",
  "B9403FE0","53187C00","53001C00","2A0003E1","90000000","9131E000","2A0103E1",
  "91080021","B8617800","12081C01","B9403BE0","53107C00","53001C00","2A0003E2",
  "90000000","9131E000","2A0203E2","910C0042","B8627800","12101C00","4A000021",
  "B94037E0","53087C00","53001C00","2A0003E2","90000000","9131E000","2A0203E2",
  "B8627800","12181C00","4A000021","B94033E0","53001C00","2A0003E2","90000000",
  "9131E000","2A0203E2","91040042","B8627800","12001C00","4A000021","F9400FE0",
  "B9400000","4A000020","B9004FE0","B9403BE0","53187C00","53001C00","2A0003E1",
  "90000000","9131E000","2A0103E1","91080021","B8617800","12081C01","B94037E0",
  "53107C00","53001C00","2A0003E2","90000000","9131E000","2A0203E2","910C0042",
  "B8627800","12101C00","4A000021","B94033E0","53087C00","53001C00","2A0003E2",
  "90000000","9131E000","2A0203E2","B8627800","12181C00","4A000021","B9403FE0",
  "53001C00","2A0003E2","90000000","9131E000","2A0203E2","91040042","B8627800",
  "12001C00","4A000021","F9400FE0","91001000","B9400000","4A000020","B9004BE0",
  "B94037E0","53187C00","53001C00","2A0003E1","90000000","9131E000","2A0103E1",
  "91080021","B8617800","12081C01","B94033E0","53107C00","53001C00","2A0003E2",
  "90000000","9131E000","2A0203E2","910C0042","B8627800","12101C00","4A000021",
  "B9403FE0","53087C00","53001C00","2A0003E2","90000000","9131E000","2A0203E2",
  "B8627800","12181C00","4A000021","B9403BE0","53001C00","2A0003E2","90000000",
  "9131E000","2A0203E2","91040042","B8627800","12001C00","4A000021","F9400FE0",
  "91002000","B9400000","4A000020","B90047E0","B94033E0","53187C00","53001C00",
  "2A0003E1","90000000","9131E000","2A0103E1","91080021","B8617800","12081C01",
  "B9403FE0","53107C00","53001C00","2A0003E2","90000000","9131E000","2A0203E2",
  "910C0042","B8627800","12101C00","4A000021","B9403BE0","53087C00","53001C00",
  "2A0003E2","90000000","9131E000","2A0203E2","B8627800","12181C00","4A000021",
  "B94037E0","53001C00","2A0003E2","90000000","9131E000","2A0203E2","91040042",
  "B8627800","12001C00","4A000021","F9400FE0","91003000","B9400000","4A000020",
  "B90043E0","F94003E0","B9404FE1","B9000001","F94003E0","91001000","B9404BE1",
  "B9000001","F94003E0","91002000","B94047E1","B9000001","F94003E0","91003000",
  "B94043E1","B9000001","910143FF","D65F03C0"
];



val _ = print_with_style sty_HEADER "\n\n\nTESTING AES CODE WITH FUNNY INSTRUCTIONS\n\n";
val _ = lift_instr_list (Arbnum.fromInt 0) (Arbnum.fromInt 0x1000000) (Arbnum.fromInt 0x400570)
    instrs






(**********)
(* BIGNUM *)
(**********)

(* precompiled bignum lib as binary blob with unspecified location *)

val instrs_bignum_from_bytes = [
  "A9BC7BFD","910003FD","F9000FA0","B90017A1","B94017A0","11000400","531F7C01",
  "0B000020","13017C00","B9003BA0","B9403BA0","94000000","F9001BA0","52800020",
  "B9003FA0","14000009","B9803FA0","D37FF800","F9401BA1","8B000020","7900001F",
  "B9403FA0","11000400","B9003FA0","B9403FA1","B9403BA0","6B00003F","54FFFEAD",
  "B94017A0","B9003FA0","14000036","F9400FA0","91000401","F9000FA1","39400000",
  "3900BFA0","B9403FA0","12000000","6B1F001F","54000320","B9403FA0","531F7C01",
  "0B000020","13017C00","11000401","93407C21","D37FF821","F9401BA2","8B010041",
  "11000400","93407C00","D37FF800","F9401BA2","8B000040","79400000","13003C02",
  "3940BFA0","53185C00","13003C00","2A000040","13003C00","53003C00","79000020",
  "14000015","B9403FA0","531F7C01","0B000020","13017C00","11000401","93407C21",
  "D37FF821","F9401BA2","8B010041","11000400","93407C00","D37FF800","F9401BA2",
  "8B000040","79400002","3940BFA0","53003C00","2A000040","53003C00","79000020",
  "B9403FA0","51000401","B9003FA1","6B1F001F","54FFF8E1","14000007","F9401BA0",
  "79400000","51000400","53003C01","F9401BA0","79000001","F9401BA0","79400000",
  "7100041F","54000149","F9401BA0","79400000","53003C00","D37FF800","F9401BA1",
  "8B000020","79400000","6B1F001F","54FFFDC0","F9401BA0","A8C47BFD","D65F03C0"
];
val instrs_bytes_from_bignum = [
  "A9BD7BFD","910003FD","F9000FA0","F9000BA1","F9400FA0","79400000","790057A0",
  "794057A0","D37FF800","F9400FA1","8B000020","79400000","7103FC1F","54000128",
  "794057A0","531F7800","53003C00","51000400","53003C01","F9400BA0","79000001",
  "14000006","794057A0","531F7800","53003C01","F9400BA0","79000001","F9400BA0",
  "79400000","53003C00","D2800201","94000000","F90013A0","52800020","79005FA0",
  "794057A0","79005BA0","14000037","79405FA0","7100041F","540002E1","794057A0",
  "D37FF800","F9400FA1","8B000020","79400000","7103FC1F","54000208","79405FA0",
  "D1000400","F94013A1","8B000020","79405BA1","D37FF821","F9400FA2","8B010041",
  "79400021","53001C21","39000001","79405FA0","51000400","79005FA0","14000018",
  "79405FA0","D1000400","F94013A1","8B000020","79405BA1","D37FF821","F9400FA2",
  "8B010041","79400021","53087C21","53003C21","53001C21","39000001","79405FA0",
  "F94013A1","8B000020","79405BA1","D37FF821","F9400FA2","8B010041","79400021",
  "53001C21","39000001","79405FA0","11000800","79005FA0","79405BA0","51000400",
  "79005BA0","F9400BA0","79400000","79405FA1","6B00003F","54FFF8C3","F94013A0",
  "A8C37BFD","D65F03C0"
];
val instrs_freebn = [
  "A9BE7BFD","910003FD","F9000FA0","F9400FA0","79400000","11000400","93407C00",
  "D37FF800","AA0003E2","52800001","F9400FA0","94000000","F9400FA0","94000000",
  "A8C27BFD","D65F03C0"
];
val instrs_internal_add_shifted = [
  "D100C3FF","F90007E0","B90007E1","B90003E2","B94003E0","11003C01","6B1F001F",
  "1A80B020","13047C00","11000400","B9002FE0","B94003E1","131F7C20","531C7C00",
  "0B000021","12000C21","4B000020","B9001FE0","B9401FE0","B94007E1","1AC02020",
  "2A0003E0","F90013E0","14000017","B9802FE0","D37FF800","F94007E1","8B000020",
  "79400000","53003C00","F94013E1","8B000020","F90013E0","B9802FE0","D37FF800",
  "F94007E1","8B000020","F94013E1","53003C21","79000001","F94013E0","D350FC00",
  "F90013E0","B9402FE0","11000400","B9002FE0","F94013E0","EB1F001F","54FFFD01",
  "9100C3FF","D65F03C0"
];
val instrs_internal_mod = [
  "A9B97BFD","910003FD","F9001FA0","B90037A1","F90017A2","B90033A3","F90013A4",
  "B9001FA5","F94017A0","79400000","790097A0","B94033A0","7100041F","540000AD",
  "F94017A0","79400400","7900DFA0","14000002","7900DFBF","B90067BF","140000DE",
  "B94067A0","6B1F001F","54000061","B9006BBF","1400000E","B98067A0","D37FF800",
  "D1000800","F9401FA1","8B000020","79400000","B9006BA0","B98067A0","D37FF800",
  "D1000800","F9401FA1","8B000020","7900001F","B94037A0","51000401","B94067A0",
  "6B00003F","54000061","B9004FBF","14000008","B98067A0","91000400","D37FF800",
  "F9401FA1","8B000020","79400000","B9004FA0","B9406BA0","D370BC01","B98067A0",
  "D37FF800","F9401FA2","8B000040","79400000","53003C00","8B000020","F9002FA0",
  "794097A0","F9402FA1","9AC00820","B90057A0","794097A1","F9402FA0","9AC10802",
  "9B017C41","CB010000","B90047A0","7940DFA1","B94057A0","9B007C20","F9002FA0",
  "B94047A0","D370BC01","B9404FA0","8B000021","F9402FA0","EB00003F","54000362",
  "B94057A0","51000400","B90057A0","7940DFA0","F9402FA1","CB000020","F9002FA0",
  "794097A1","B94047A0","0B000020","12003C00","B90047A0","794097A1","B94047A0",
  "6B00003F","54000168","B94047A0","D370BC01","B9404FA0","8B000021","F9402FA0",
  "EB00003F","54000082","B94057A0","51000400","B90057A0","B90053BF","B94033A0",
  "51000400","B90063A0","14000037","B94057A1","B98063A0","D37FF800","F94017A2",
  "8B000040","79400000","53003C00","9B007C20","F9002FA0","B94053A0","F9402FA1",
  "8B000020","F9002FA0","F9402FA0","D350FC00","B90053A0","F9402FA0","53003C01",
  "B94067A2","B94063A0","0B000040","93407C00","D37FF800","F9401FA2","8B000040",
  "79400000","6B00003F","54000089","B94053A0","11000400","B90053A0","B94067A1",
  "B94063A0","0B000020","93407C00","D37FF800","F9401FA1","8B000020","B94067A2",
  "B94063A1","0B010041","93407C21","D37FF821","F9401FA2","8B010041","79400022",
  "F9402FA1","53003C21","4B010041","53003C21","79000001","B94063A0","51000400",
  "B90063A0","B94063A0","6B1F001F","54FFF90A","B94053A1","B9406BA0","6B00003F",
  "54000620","F9002FBF","B94033A0","51000400","B90063A0","14000026","B98063A0",
  "D37FF800","F94017A1","8B000020","79400000","53003C00","F9402FA1","8B000020",
  "F9002FA0","B94067A1","B94063A0","0B000020","93407C00","D37FF800","F9401FA1",
  "8B000020","79400000","53003C00","F9402FA1","8B000020","F9002FA0","B94067A1",
  "B94063A0","0B000020","93407C00","D37FF800","F9401FA1","8B000020","F9402FA1",
  "53003C21","79000001","F9402FA0","D350FC00","F9002FA0","B94063A0","51000400",
  "B90063A0","B94063A0","6B1F001F","54FFFB2A","B94057A0","51000400","B90057A0",
  "F94013A0","EB1F001F","540001A0","B94037A1","B94033A0","4B000021","B94067A0",
  "4B000020","531C6C01","B9401FA0","0B000020","2A0003E2","B94057A1","F94013A0",
  "94000000","B94067A0","11000400","B90067A0","B94037A1","B94033A0","4B000021",
  "B94067A0","6B00003F","54FFE3CA","A8C77BFD","D65F03C0"
];
val instrs_internal_mul = [
  "D10103FF","F9000FE0","F9000BE1","F90007E2","B90007E3","B9003BFF","14000009",
  "B9803BE0","D37FF800","F94007E1","8B000020","7900001F","B9403BE0","11000400",
  "B9003BE0","B94007E0","531F7801","B9403BE0","6B00003F","54FFFE8C","B94007E0",
  "51000400","B9003FE0","14000043","B9803FE0","D37FF800","F9400FE1","8B000020",
  "79400000","53003C00","F90017E0","F9001BFF","B94007E0","51000400","B9003BE0",
  "1400002A","B9803BE0","D37FF800","F9400BE1","8B000020","79400000","53003C01",
  "F94017E0","9B007C20","F9401BE1","8B000020","F9001BE0","B9403FE1","B9403BE0",
  "0B000020","93407C00","91000400","D37FF800","F94007E1","8B000020","79400000",
  "53003C00","F9401BE1","8B000020","F9001BE0","B9403FE1","B9403BE0","0B000020",
  "93407C00","91000400","D37FF800","F94007E1","8B000020","F9401BE1","53003C21",
  "79000001","F9401BE0","D350FC00","F9001BE0","B9403BE0","51000400","B9003BE0",
  "B9403BE0","6B1F001F","54FFFAAA","B9803FE0","D37FF800","F94007E1","8B000020",
  "F9401BE1","53003C21","79000001","B9403FE0","51000400","B9003FE0","B9403FE0",
  "6B1F001F","54FFF78A","910103FF","D65F03C0"
];
val instrs_newbn = [
  "A9BD7BFD","910003FD","B9001FA0","B9401FA0","11000400","93407C00","D37FF800",
  "D2800201","94000000","F90017A0","F94017A0","EB1F001F","54000061","D2800000",
  "1400000E","B9401FA0","11000400","93407C00","D37FF800","AA0003E2","52800001",
  "F94017A0","94000000","B9401FA0","53003C01","F94017A0","79000001","F94017A0",
  "A8C37BFD","D65F03C0"
];

val instrs_bignumlib = instrs_bignum_from_bytes @
             instrs_bytes_from_bignum @
             instrs_freebn @
             instrs_internal_add_shifted @
             instrs_internal_mod @
             instrs_internal_mul @
             instrs_newbn;


val _ = print_with_style sty_HEADER "\n\n\nTESTING BIGNUM LIB CODE\n\n";
val _ = lift_instr_list (Arbnum.fromInt 0) (Arbnum.fromInt 0x1000000) (Arbnum.fromInt 0x400570)
    instrs_bignumlib



(*****************)
(* final summary *)
(*****************)

val expected_failed_hexcodes:string list = [];

val _ = final_results expected_failed_hexcodes;
