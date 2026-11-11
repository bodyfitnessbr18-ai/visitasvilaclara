-- Recria a agenda pública com somente os dados necessários.
-- Não depende da coluna opcional enfermos.ultima_visita.
create or replace view public.visitas_publicas
with (security_barrier = true, security_invoker = false)
as
with
hoje as (
  select (now() at time zone 'America/Sao_Paulo')::date as dia
),
agendadas as (
  select
    v.data_visita::date as data_visita,
    v.horario::text as horario,
    e.nome::text as enfermo_nome,
    concat_ws(', ',
      nullif(trim(e.endereco), ''),
      nullif(trim(e.numero), ''),
      nullif(trim(e.bairro), ''),
      nullif(trim(e.cidade), '')
    ) as endereco_completo,
    'Agendada'::text as origem,
    v.enfermo_id
  from public.visitas v
  join public.enfermos e on e.id = v.enfermo_id
  cross join hoje h
  where v.status = 'agendada'
    and v.data_visita::date >= h.dia
    and e.ativo = true
),
contagem as (
  select count(*)::int as total from agendadas
),
ultima_visita as (
  select e.id, e.nome, e.endereco, e.numero, e.bairro, e.cidade,
         max(v.data_visita)::date as ultima_data
  from public.enfermos e
  left join public.visitas v
    on v.enfermo_id = e.id and v.status = 'realizada'
  where e.ativo = true
  group by e.id, e.nome, e.endereco, e.numero, e.bairro, e.cidade
),
fila as (
  select u.*,
         row_number() over (order by u.ultima_data nulls first, u.nome) as posicao
  from ultima_visita u
  where not exists (select 1 from agendadas a where a.enfermo_id = u.id)
),
primeira_quarta as (
  select h.dia + (
    (3 - extract(dow from h.dia)::int + 7) % 7
    + case when extract(dow from h.dia)::int = 3 then 7 else 0 end
  ) as dia
  from hoje h
),
quartas_livres as (
  select gs::date as dia,
         row_number() over (order by gs) as posicao
  from primeira_quarta q
  cross join generate_series(q.dia::timestamp, (q.dia + 140)::timestamp, interval '7 days') gs
  where not exists (select 1 from agendadas a where a.data_visita = gs::date)
),
previstas as (
  select q.dia::date as data_visita,
         null::text as horario,
         f.nome::text as enfermo_nome,
         concat_ws(', ',
           nullif(trim(f.endereco), ''),
           nullif(trim(f.numero), ''),
           nullif(trim(f.bairro), ''),
           nullif(trim(f.cidade), '')
         ) as endereco_completo,
         'Previsão da fila'::text as origem,
         f.id as enfermo_id
  from fila f
  join quartas_livres q on q.posicao = f.posicao
  cross join contagem c
  where c.total < 3 and f.posicao <= 3 - c.total
)
select data_visita, horario, enfermo_nome, endereco_completo, origem
from (
  select data_visita, horario, enfermo_nome, endereco_completo, origem from agendadas
  union all
  select data_visita, horario, enfermo_nome, endereco_completo, origem from previstas
) agenda
order by data_visita, horario nulls last
limit 3;

revoke all on table public.visitas_publicas from public;
grant usage on schema public to anon;
grant select on table public.visitas_publicas to anon;
revoke all on table public.enfermos from anon;
revoke all on table public.visitas from anon;
