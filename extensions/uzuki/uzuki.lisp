;;;; uzuki.lisp

(in-package #:april-xt.uzuki)

"An extension to April mapping Japanese kanji to the standard APL lexicon."

;; add ⍨'s alias to its category
(push #\向 *value-composable-lexical-operators*)
;; "｛⎕IOー向投２形向絶牛　馬｝"
;; ｛出１　馬下積上３　４＝＋折付１　０　¯１続積回［１］１　０　¯１回別込馬｝
;; 積　点
(extend-vex-idiom
 april
 (system :closure-wrapping "（()）" :function-wrapping "｛{}｝" :axis-wrapping "［[]］"
         :string-delimiters "'\"＇" :number-spacers "_＿"
         :axis-separators ";；" :path-separators ".．" :negative-signs "¯￣")
 (utilities :process-fn-op-specs #'process-fnspecs
            :format-value (let ((base-function (of-utilities this-idiom :format-value))
                                (matching-symbols (vector '⍵ '⍹ '⍵⍵ '⍺ '⍶ '⍺⍺)))
                            ;; aliases of argument/operand symbols with cow/horse derived
                            ;; characters referencing Gozu and Mezu
                            (lambda (idiom-name symbols element)
                              (let ((sym-pos (position (aref element 0) "馬媽馭牛犢牧")))
                                (if sym-pos (aref matching-symbols sym-pos)
                                    (funcall base-function idiom-name symbols element)))))
            :match-numeric-character
            (lambda (char) (or (digit-char-p char) (position char ".．_＿¯￣eEjJrR" :test #'char=)))
            :match-token-character
            (lambda (char) (or (is-alphanumeric char)
                               (position char ".．_＿⎕∆⍙¯￣" :test #'char=))))
 (functions (with (:name :japanese-kanji-function-aliases))
            (\＋ (has :title "プラス") ;; 1￣
                 (alias-of +))        ;; ⌹←→
            (\－ (has :title "マイナス")
                 (alias-of -))
            (倍 (has :title "バイ")
                (alias-of ×))
            (分 (has :title "分かれる／ブン")
                (alias-of ÷))
            (巾 (has :title "べき")
                (alias-of *))
            (元 (has :title "もと／ゲン")
                (alias-of ⍟))
            (絶 (has :title "絶対／ゼツ")
                (alias-of \|))
            (階 (has :title "カイ")
                (alias-of !))
            (高 (has :title "高い／コウ")
                (alias-of ⌈))
            (低 (has :title "低い／テイ")
                (alias-of ⌊))
            (投 (has :title "投げる／トウ")
                (alias-of ?))
            (丸 (has :title "まる／ガン")
                (alias-of ○))
            (影 (has :title "かげ／エイ")
                (alias-of ~))
            (\＜ (has :title "Less than")
                 (alias-of <))
            (少 (has :title "少ない／ショウ")
                (alias-of ≤))
            (\＝ (has :title "Equal")
                 (alias-of =))
            (多 (has :title "多い／タ")
                (alias-of ≥))
            (\＞ (has :title "Greater than")
                 (alias-of >))
            (不 (has :title "フ")
                (alias-of ≠))
            (上 (has :title "上がる／ジョウ")
                (alias-of ∧))
            (止 (has :title "止まる／シ")
                (alias-of ⍲))
            (下 (has :title "下がる／カ")
                (alias-of ∨))
            (支 (has :title "支える／シ")
                (alias-of ⍱))
            (指 (has :title "指数／シ")
                (alias-of ⍳))
            (形 (has :title "かたち／ケイ")
                (alias-of ⍴))
            (号 (has :title "ゴウ")
                (alias-of ⌷))
            (深 (has :title "深い／シン")
                (alias-of ≡))
            (検 (has :title "ケン") ;; meaning fits?
                (alias-of ≢))
            (列 (has :title "レツ")
                (alias-of ∊))
            (探 (has :title "探す／タン")
                (alias-of ⍷))
            (間 (has :title "あいだ／カン")
                (alias-of ⍸))
            (付 (has :title "付ける／フ")
                (alias-of \,))
            (立 (has :title "立つ／リツ")
                (alias-of ⍪))
            (取 (has :title "取る／シュ")
                (alias-of ↑))
            (落 (has :title "落とす／ラク")
                (alias-of ↓))
            (込 (has :title "込む")
                (alias-of ⊂))
            (寄 (has :title "寄す／キ")
                (alias-of ⊆))
            (出 (has :title "出る／シュツ")
                (alias-of ⊃))
            (交 (has :title "交わる／コウ")
                (alias-of ∩))
            (合 (has :title "合わせる／ゴウ")
                (alias-of ∪))
            (回 (has :title "回す／カイ")
                (alias-of ⌽))
            (順 (has :title "順列／ジュン")
                (alias-of ⍉))
            (折 (has :title "折る／セツ")
                (alias-of /))
            (越 (has :title "越える／キョウ")
                (alias-of \\))
            (昇 (has :title "昇る／ショウ")
                (alias-of ⍋))
            (降 (has :title "降りる／コウ")
                (alias-of ⍒))
            (符 (has :title "符号／フ")
                (alias-of ⊤))
            (復 (has :title "復号／フク")
                (alias-of ⊥))
            (右 (has :title "みぎ／ウ")
                (alias-of ⊢))
            (左 (has :title "ひだり／サ")
                (alias-of ⊣))
            (印 (has :title "印刷／イン")
                (alias-of ⍕))
            (入 (has :title "入力／ニュウ")
                (alias-of ⍎))
            ;; (之 (has :title "の")
            ;;     (alias-of ←))
            ;; (行 (has :title "行く／ギョウ")
            ;;     (alias-of →))
            )
 (operators (with (:name :japanese-kanji-operator-aliases))
            (折 (has :title "折る／セツ")
                (alias-of /))
            (越 (has :title "越える／キョウ")
                (alias-of \\))
            (別 (has :title "ベツ")
                (alias-of \¨))
            (向 (has :title "向かう／コウ")
                (alias-of ⍨))
            (集 (has :title "集まる／シュウ")
                (alias-of ⌸))
            (積 (has :title "セキ")
                (alias-of \.))
            (続 (has :title "続く／ゾク")
                (alias-of ∘))
            (備 (has :title "備える／ビ") ;; meaning fits?
                (alias-of ⍛))
            (括 (has :title "括る／カツ")
                (alias-of ⍤))
            (増 (has :title "増す／ゾウ")
                (alias-of ⍥))
            (連 (has :title "連続／レン")
                (alias-of ⍣))
            (撰 (has :title "選ぶ／セン")
                (alias-of @))
            (畳 (has :title "たたみ／ジョウ")
                (alias-of ⌺)))
 (statements (with (:name :japanese-kanji-statement-aliases))
             (叉 (has :title "また／サ")
                 (alias-of $))))

