-- Acesso público somente de leitura à agenda das próximas visitas.
-- A view expõe apenas nome, data, horário e endereço das visitas agendadas futuras.
-- Não libera acesso público direto às tabelas de enfermos ou visitas.

create or replace view public.visitas_publicas
with (security_barrier = true, security_invoker = false)
as
select
  v.id,
  v.data_visita,
  v.horario,
  e.nome as enfermo_nome,
  concat_ws(', ',
    nullif(trim(e.endereco), ''),
    nullif(trim(e.numero), ''),
    nullif(trim(e.bairro), ''),
    nullif(trim(e.cidade), '')
  ) as endereco_completo
from public.visitas as v
join public.enfermos as e on e.id = v.enfermo_id
where v.status = 'agendada'
  and v.data_visita >= current_date
  and e.ativo = true;

revoke all on table public.visitas_publicas from public;
grant usage on schema public to anon;
grant select on table public.visitas_publicas to anon;

-- Bloqueia consultas diretas anônimas às tabelas que contêm dados pessoais.
revoke all on table public.enfermos from anon;
revoke all on table public.visitas from anon;
