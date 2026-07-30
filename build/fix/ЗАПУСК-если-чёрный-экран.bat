@echo off
rem Принудительно совместимый рендер (лечит чёрный экран). Обычно уже не нужно -
rem игра и так стартует в этом режиме.
for %%f in ("%~dp0*.exe") do (
    start "" "%%f" --rendering-method gl_compatibility
    goto done
)
pause
:done
