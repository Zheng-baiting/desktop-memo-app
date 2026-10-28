# Python 原型源码归档

归档日期：2026-10-28。

本分支保存清理本机项目时发现尚未纳入 Git 的早期 Python/Tkinter 原型：根目录 app.py、start-memo.bat、desktop_memo/、tests/test_storage.py 和空 data/.gitkeep。

这是历史原型，不取代 main 分支的 Flutter 便利贴 1.4.1；没有为它补造新的产品发行版本。个人便签、恢复数据、缓存和构建产物未上传。

Python 存储测试：python -m unittest discover -s tests -p "test_*.py"。测试使用临时目录。运行原型需要带 Tkinter 的 Python，入口为 python app.py；运行后数据保存在 data/notes.json，不与当前便利贴的数据混用。
