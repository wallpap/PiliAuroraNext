import unittest

from tool.check_native_comments import added_comments, in_scope, inventory


class CommentPolicyTest(unittest.TestCase):
    def test_strings_and_preprocessor_tokens_do_not_count(self):
        for name, source, expected in [
            ("file.py", 'url = "https://test#part"\n# comment\n', "# comment"),
            (
                "file.cc",
                '#include <vector>\nconst char* url = "//";\n// comment\n',
                "// comment",
            ),
            ("file.ps1", 'Write-Output "# literal"\n# comment\n', "# comment"),
            ("file.yml", 'key: "# literal"\n# comment\n', "# comment"),
            (
                "file.xml",
                '<node label="<!-- literal --&gt;"/>\n<!-- comment -->\n',
                "<!-- comment -->",
            ),
            ("CMakeLists.txt", 'set(value "# literal")\n# comment\n', "# comment"),
        ]:
            with self.subTest(name=name):
                comments, touched, removable = inventory(name, source)
                self.assertEqual([comment.text for comment in comments], [expected])
                self.assertEqual(touched, removable)

    def test_multiline_and_inline(self):
        comments, touched, removable = inventory(
            "example.cpp",
            "int sample; /* start\r\n\r\nfinish */\r\n",
        )
        self.assertEqual((comments[0].line, comments[0].endLine), (1, 3))
        self.assertEqual(touched, {1, 2, 3})
        self.assertEqual(removable, {2, 3})

    def test_cmake_quoted_bracket_and_escaped_hashes_are_not_comments(self):
        source = (
            'install(CODE "\nfile(REMOVE \\"# not a comment\\")\n")\n'
            "set(value [=[# literal]=])\n"
            r"set(other \#escaped)"
            "\n#[=[keep\nthis]=]\n"
            "# comment"
        )
        comments, _, removable = inventory("CMakeLists.txt", source)
        self.assertEqual(
            [comment.text for comment in comments], ["#[=[keep\nthis]=]", "# comment"]
        )
        self.assertEqual(removable, {6, 7, 8})

    def test_ratchet_checks_text_and_multiplicity(self):
        before = "# inherited\n# may be removed\n"
        self.assertEqual(
            list(added_comments("probe.py", before, "x = 3\r\n# inherited\r\n")), []
        )
        self.assertEqual(
            [
                entry.line
                for entry in added_comments(
                    "probe.py",
                    before,
                    "# inherited\n# replacement\n# inherited",
                )
            ],
            [2, 3],
        )

    def test_patch_inventory_ignores_upstream_context_and_removed_comments(self):
        source = (
            "diff --git a/example.dart b/example.dart\n"
            "--- a/example.dart\n+++ b/example.dart\n@@ -1,3 +1,3 @@\n"
            " // upstream context\n-// removed\n+// owned\n const example = '/* string */';\n"
        )
        comments, touched, removable = inventory("framework.patch", source)
        self.assertEqual([comment.text for comment in comments], ["// owned"])
        self.assertEqual(touched, {7})
        self.assertEqual(removable, {7})

    def test_upstream_sources_are_excluded(self):
        self.assertFalse(in_scope("third_party/package/tool.py"))
        self.assertFalse(in_scope("tool/protocol/schema/bilibili/account.proto"))
        self.assertFalse(in_scope("assets/shaders/Anime4K_Restore_CNN_M.glsl"))
        self.assertTrue(in_scope("assets/shaders/Windows_ChromaClamp.glsl"))
        self.assertTrue(in_scope("windows/runner/Runner.rc"))
        self.assertTrue(in_scope("android/app/src/main/AndroidManifest.xml"))

    def test_inno_uses_semicolon_comments_and_pascal_only_inside_code(self):
        source = (
            '#define AppName "sample"\n'
            "[Setup]\n; section note\nAppName={#AppName}\n"
            "[Code]\n{ code note }\n"
            '[Icons]\nName: "{cm:AppName}"; Filename: "{app}\\demo.exe"\n'
        )
        comments, _, _ = inventory("setup.iss", source)
        self.assertEqual(
            [comment.text for comment in comments], ["; section note", "{ code note }"]
        )
